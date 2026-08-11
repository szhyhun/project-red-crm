class Api::V1::AppointmentsController < Api::V1::BaseController
  rescue_from ActiveRecord::StatementInvalid, with: :render_schedule_conflict

  def index
    return render json: { error: "forbidden" }, status: :forbidden unless current_user.internal?

    appointments = Current.organization.appointments.includes(:listing, :assigned_user).order(:starts_at)
    render json: { appointments: appointments.map { |appointment| serialize(appointment) } }
  end

  def create
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :update?
    appointment = listing.appointments.build(appointment_params.merge(organization: Current.organization))

    if appointment.save
      record_activity(appointment, "appointment.created")
      render json: { appointment: serialize(appointment) }, status: :created
    else
      render_validation_errors(appointment)
    end
  end

  def update
    appointment = Current.organization.appointments.includes(:listing).find(params[:id])
    authorize appointment.listing, :update?

    if appointment.update(appointment_params)
      record_activity(appointment, "appointment.updated")
      render json: { appointment: serialize(appointment) }
    else
      render_validation_errors(appointment)
    end
  end

  def destroy
    appointment = Current.organization.appointments.includes(:listing).find(params[:id])
    authorize appointment.listing, :update?
    appointment.destroy!
    record_activity(appointment, "appointment.deleted")
    head :no_content
  end

  private

  def appointment_params
    params.require(:appointment).permit(:assigned_user_id, :status, :starts_at, :ends_at, :notes, :calendar_color)
  end

  def serialize(appointment)
    {
      id: appointment.id,
      listing_id: appointment.listing_id,
      address: appointment.listing.address,
      status: appointment.status,
      starts_at: appointment.starts_at,
      ends_at: appointment.ends_at,
      notes: appointment.notes,
      calendar_color: appointment.calendar_color,
      assigned_user: appointment.assigned_user && appointment.assigned_user.slice(:id, :name, :email, :role)
    }
  end

  def record_activity(appointment, event_type)
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: appointment, event_type: event_type)
  end

  def render_schedule_conflict(error)
    raise error unless error.cause.is_a?(PG::ExclusionViolation)

    render json: { error: "schedule_conflict", details: { assigned_user: ["already has an appointment during this time"] } }, status: :unprocessable_entity
  end
end
