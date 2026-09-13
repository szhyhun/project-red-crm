class Api::V1::ClientMembershipsController < Api::V1::BaseController
  def index
    account = policy_scope(ClientAccount).find(params[:client_account_id])
    authorize account, :view?
    memberships = account.client_memberships.includes(:user).order(:created_at, :id)

    render json: { client_memberships: memberships.map { |membership| serialize(membership) } }
  end

  # The teams a person belongs to, including invitations they have not accepted.
  def mine
    skip_policy_scope
    memberships = current_user.client_memberships.includes(:client_account).order(:created_at, :id)
    memberships.each { |membership| authorize membership, :view? }

    render json: { client_memberships: memberships.map { |membership| serialize(membership) } }
  end

  def create
    account = policy_scope(ClientAccount).find(params[:client_account_id])
    authorize account.client_memberships.build(user: current_user), :create?
    result = ClientMemberships::Invite.call(
      account:, actor: current_user, email: invite_params[:email], name: invite_params[:name], role: invite_params[:role]
    )
    raise result.failure.original_error || result.failure if result.failure?
    membership = result.fetch(:membership)

    render json: { client_membership: serialize(membership) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def update
    membership = visible_membership
    authorize membership, :update?
    attributes = update_params
    # A role is an admin's to change; the landing team and notifications are the
    # person's own.
    authorize membership, :manage? if attributes.key?(:role)
    raise Pundit::NotAuthorizedError if attributes.key?(:is_default) && membership.user_id != current_user.id

    membership.update!(attributes)
    record(membership, "client_membership.updated", attributes.slice(:role, :is_default).to_h)
    render json: { client_membership: serialize(membership.reload) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def accept
    membership = visible_membership
    authorize membership, :update?
    raise Pundit::NotAuthorizedError unless membership.user_id == current_user.id

    membership.accept!
    record(membership, "client_membership.accepted")
    render json: { client_membership: serialize(membership.reload) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def destroy
    membership = visible_membership
    authorize membership, :destroy?
    membership.revoke!
    record(membership, "client_membership.revoked")

    render json: { client_membership: serialize(membership.reload) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  private

  def visible_membership
    ClientMembershipPolicy::Scope.new(current_user, ClientMembership).resolve.includes(:user, :client_account).find(params[:id])
  end

  def invite_params
    params.require(:client_membership).permit(:email, :name, :role)
  end

  def update_params
    params.require(:client_membership)
      .permit(:role, :is_default, :listing_delivery_notification_enabled)
      .to_h.symbolize_keys
  end

  def record(membership, event_type, payload = {})
    ActivityEvent.create!(
      organization: membership.client_account.organization,
      actor: current_user,
      subject: membership,
      event_type:,
      payload: payload.merge(client_account_id: membership.client_account_id)
    )
  end

  def serialize(membership)
    membership.slice(:id, :client_account_id, :role, :status, :is_default, :invitation_accepted_at,
                     :listing_delivery_notification_enabled, :created_at).merge(
      user: membership.user.slice(:id, :name, :email),
      client_account: membership.client_account.slice(:id, :name, :kind),
      capabilities: ClientMembershipPolicy.new(current_user, membership).capabilities
    )
  end
end
