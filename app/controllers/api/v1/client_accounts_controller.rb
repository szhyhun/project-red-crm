class Api::V1::ClientAccountsController < Api::V1::BaseController
  def index
    accounts = policy_scope(ClientAccount).order(:name)
    render json: { client_accounts: accounts.map { |account| serialize(account) } }
  end

  def create
    account = Current.organization.client_accounts.build(client_account_params)
    authorize account

    if account.save
      render json: { client_account: serialize(account) }, status: :created
    else
      render_validation_errors(account)
    end
  end

  def invite
    account = policy_scope(ClientAccount).find(params[:id])
    authorize account, :invite?
    user = nil

    ClientAccount.transaction do
      user = User.invite!(invite_params.merge(organization: Current.organization), current_user)
      raise ActiveRecord::RecordInvalid.new(user) if user.errors.any?

      account.client_memberships.find_or_create_by!(user: user) { |membership| membership.role = invite_params[:membership_role] }
      account.conversations.client.find_each do |conversation|
        conversation.conversation_memberships.find_or_create_by!(user: user) { |membership| membership.role = :participant }
      end
    end

    render json: { client_user: user.slice(:id, :name, :email, :role) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  private

  def client_account_params
    params.require(:client_account).permit(:name, :kind, :email, :phone, :brokerage_name)
  end

  def invite_params
    params.require(:client_user).permit(:name, :email, :membership_role).tap do |attributes|
      attributes[:role] = attributes[:membership_role] == "member" ? "client_member" : "client_admin"
      attributes[:membership_role] = "admin" unless %w[admin member].include?(attributes[:membership_role])
    end
  end

  def serialize(account)
    account.slice(:id, :name, :kind, :email, :phone, :brokerage_name)
  end
end
