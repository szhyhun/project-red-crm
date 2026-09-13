class Api::V1::ClientMembershipInvitationsController < Api::V1::BaseController
  def create
    membership = policy_scope(ClientMembership).includes(:user, :client_account).find(params[:client_membership_id])
    authorize membership, :manage?
    result = ClientMemberships::SendInvitation.call(membership:, actor: current_user)
    if result.failure?
      return render json: { error: result.failure.code, details: { base: [ result.failure.message ] } }, status: :unprocessable_content
    end

    render json: { client_membership: { id: membership.id, invitation_sent_at: membership.user.reload.invitation_sent_at } }, status: :created
  end
end
