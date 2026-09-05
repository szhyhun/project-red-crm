class Api::V1::UserGroupMembershipsController < Api::V1::BaseController
  before_action :set_group

  def create
    authorize @group, :manage?
    user = Current.organization.users.find(membership_params[:user_id])
    membership = @group.user_group_memberships.build(user:)

    if membership.save
      render json: { member: user.slice(:id, :name, :email, :role) }, status: :created
    else
      render_validation_errors(membership)
    end
  end

  def destroy
    authorize @group, :manage?
    @group.user_group_memberships.find_by!(user_id: params[:id]).destroy!
    head :no_content
  end

  private

  def set_group
    @group = policy_scope(UserGroup).find(params[:user_group_id])
  end

  def membership_params
    params.require(:member).permit(:user_id)
  end
end
