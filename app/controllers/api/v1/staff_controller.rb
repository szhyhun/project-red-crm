class Api::V1::StaffController < Api::V1::BaseController
  def index
    authorize User, :index?
    users = Current.organization.users.where(role: manageable_roles).order(:name)
    render json: { staff: users.map { |user| serialize(user) } }
  end

  def create
    authorize User, :invite?
    user = User.invite!(invite_params.merge(organization: Current.organization), current_user)

    if user.errors.empty?
      render json: { staff_member: serialize(user) }, status: :created
    else
      render_validation_errors(user)
    end
  end

  def update
    user = Current.organization.users.where(role: manageable_roles).find(params[:id])
    authorize user
    attributes = update_params

    if user == current_user && changes_access?(user, attributes)
      return render json: { error: "You cannot change your own role or access status." }, status: :unprocessable_content
    end

    if removing_last_admin?(user, attributes)
      return render json: { error: "The organization must retain an active administrator." }, status: :unprocessable_content
    end

    if user.update(attributes)
      render json: { staff_member: serialize(user) }
    else
      render_validation_errors(user)
    end
  end

  private

  def serialize(user)
    user.slice(:id, :name, :email, :role, :status).merge(
      invitation_pending: user.invitation_sent_at.present? && user.invitation_accepted_at.blank?
    )
  end

  def invite_params
    params.require(:staff_member).permit(:name, :email, :role).tap do |attributes|
      attributes[:role] = "production_staff" unless manageable_roles.include?(attributes[:role])
    end
  end

  def update_params
    params.require(:staff_member).permit(:name, :role, :status).tap do |attributes|
      attributes.delete(:role) unless manageable_roles.include?(attributes[:role])
      attributes.delete(:status) unless %w[active suspended].include?(attributes[:status])
    end
  end

  def manageable_roles
    %w[organization_admin manager production_staff]
  end

  def changes_access?(user, attributes)
    (attributes[:role].present? && attributes[:role] != user.role) ||
      (attributes[:status].present? && attributes[:status] != user.status)
  end

  def removing_last_admin?(user, attributes)
    return false unless user.organization_admin? && user.active?

    removes_access = attributes[:role].present? && attributes[:role] != "organization_admin"
    removes_access ||= attributes[:status] == "suspended"
    removes_access && Current.organization.users.organization_admin.active.where.not(id: user.id).none?
  end
end
