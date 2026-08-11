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

  private

  def client_account_params
    params.require(:client_account).permit(:name, :kind, :email, :phone, :brokerage_name)
  end

  def serialize(account)
    account.slice(:id, :name, :kind, :email, :phone, :brokerage_name)
  end
end
