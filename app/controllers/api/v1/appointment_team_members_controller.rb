class Api::V1::AppointmentTeamMembersController < Api::V1::BaseController
  before_action :set_appointment

  def create
    member = @appointment.appointment_team_members.build(member_params)
    if member.save
      render json: { appointment_team_member: serialize(member) }, status: :created
    else
      render_validation_errors(member)
    end
  end

  def destroy
    @appointment.appointment_team_members.find(params[:id]).destroy!
    head :no_content
  end

  private

  def set_appointment
    @appointment = Current.organization.appointments.find(params[:appointment_id])
    authorize @appointment.listing, :update?
  end

  def member_params
    params.require(:appointment_team_member).permit(:user_id, :role)
  end

  def serialize(member)
    member.slice(:id, :user_id, :role).merge(user: member.user.slice(:id, :name, :email, :role))
  end
end
