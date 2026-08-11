class Api::V1::StaffController < Api::V1::BaseController
  def index
    users = Current.organization.users.active.where.not(role: %w[client_admin client_member]).order(:name)
    render json: { staff: users.map { |user| serialize(user) } }
  end

  private

  def serialize(user)
    user.slice(:id, :name, :email, :role)
  end
end
