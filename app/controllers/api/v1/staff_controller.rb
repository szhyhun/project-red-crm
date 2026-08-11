class Api::V1::StaffController < Api::V1::BaseController
  def index
    authorize User, :index?
    users = Current.organization.users.active.where.not(role: %w[client_admin client_member]).order(:name)
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

  private

  def serialize(user)
    user.slice(:id, :name, :email, :role).merge(invitation_pending: user.invitation_sent_at.present? && user.invitation_accepted_at.blank?)
  end

  def invite_params
    params.require(:staff_member).permit(:name, :email, :role).tap do |attributes|
      attributes[:role] = "production_staff" unless %w[manager production_staff].include?(attributes[:role])
    end
  end
end
