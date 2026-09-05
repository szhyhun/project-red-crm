class Api::V1::UserGroupsController < Api::V1::BaseController
  def index
    authorize UserGroup, :index?
    groups = policy_scope(UserGroup).includes(:users).order(:name)
    render json: { user_groups: groups.map { |group| serialize(group) } }
  end

  def create
    group = Current.organization.user_groups.build(group_params)
    authorize group

    group.save ? render(json: { user_group: serialize(group) }, status: :created) : render_validation_errors(group)
  end

  def update
    group = policy_scope(UserGroup).find(params[:id])
    authorize group

    group.update(group_params) ? render(json: { user_group: serialize(group.reload) }) : render_validation_errors(group)
  end

  def destroy
    group = policy_scope(UserGroup).find(params[:id])
    authorize group
    group.destroy!
    head :no_content
  end

  private

  def group_params
    params.require(:user_group).permit(:name, :slug, :description)
  end

  def serialize(group)
    group.slice(:id, :name, :slug, :description).merge(
      capabilities: capabilities_for(group),
      members: group.users.map { |user| user.slice(:id, :name, :email, :role) }
    )
  end
end
