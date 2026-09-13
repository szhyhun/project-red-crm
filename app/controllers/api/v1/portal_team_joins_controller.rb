class Api::V1::PortalTeamJoinsController < Api::V1::BaseController
  def create
    authorize :client_portal, :update?
    result = ClientMemberships::JoinByAffiliateCode.call(user: current_user, code: params.require(:affiliate_id))
    if result.failure?
      return render json: { error: result.failure.code, details: { base: [ result.failure.message ] } }, status: :unprocessable_content
    end

    membership = result.fetch(:membership)
    render json: { client_membership: membership.slice(:id, :role, :status, :is_default).merge(
      client_account: membership.client_account.slice(:id, :name, :kind)
    ) }, status: :created
  end
end
