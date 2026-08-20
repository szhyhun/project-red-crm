class Api::V1::CustomerTeamMembershipsController < Api::V1::BaseController
  def create
    team = policy_scope(CustomerTeam).find(params[:customer_team_id])
    authorize team, :update?
    account = policy_scope(ClientAccount).find(membership_params[:client_account_id])
    membership = team.customer_team_memberships.find_or_initialize_by(client_account: account)
    membership.assign_attributes(membership_params.except(:client_account_id))
    membership.save!
    render json: { customer_team_membership: serialize(membership) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def destroy
    team = policy_scope(CustomerTeam).find(params[:customer_team_id])
    authorize team, :update?
    membership = team.customer_team_memberships.find(params[:id])
    membership.destroy!
    head :no_content
  end

  private

  def membership_params
    params.require(:customer_team_membership).permit(:client_account_id, :primary)
  end

  def serialize(membership)
    membership.slice(:id, :customer_team_id, :client_account_id, :primary)
  end
end
