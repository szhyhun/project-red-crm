class Api::V1::AppointmentsController < Api::V1::BaseController
  rescue_from ActiveRecord::StatementInvalid, with: :render_schedule_conflict

  def index
    return render json: { error: "forbidden" }, status: :forbidden unless current_user.internal?

    appointments = appointment_scope.order(:starts_at)
    render json: { appointments: appointments.map { |appointment| serialize(appointment) } }
  end

  def create
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :update?
    appointment = listing.appointments.build(appointment_params.merge(organization: Current.organization))

    if appointment.save
      appointment.appointment_events.create!(actor: current_user, event_type: "created", changeset: appointment.previous_changes)
      record_activity(appointment, "appointment.created")
      render json: { appointment: serialize(appointment) }, status: :created
    else
      render_validation_errors(appointment)
    end
  end

  def update
    appointment = appointment_scope.find(params[:id])
    authorize appointment.listing, :update?

    if appointment.update(appointment_params)
      event_type = if appointment.previous_changes.key?("request_status") && appointment.request_status == "approved"
        "customer_reschedule_approved"
      elsif appointment.previous_changes.key?("request_status") && appointment.request_status == "declined"
        "customer_reschedule_declined"
      else
        "updated"
      end
      appointment.appointment_events.create!(actor: current_user, event_type: event_type, changeset: appointment.previous_changes)
      record_activity(appointment, "appointment.updated")
      render json: { appointment: serialize(appointment) }
    else
      render_validation_errors(appointment)
    end
  end

  def destroy
    appointment = appointment_scope.find(params[:id])
    authorize appointment.listing, :update?
    appointment.update!(status: :cancelled)
    appointment.appointment_events.create!(actor: current_user, event_type: "cancelled", changeset: appointment.previous_changes)
    record_activity(appointment, "appointment.cancelled")
    render json: { appointment: serialize(appointment) }
  end

  private

  def appointment_params
    params.require(:appointment).permit(:order_id, :assigned_user_id, :status, :request_status, :starts_at, :ends_at, :completed_at, :notes, :calendar_color)
  end

  def serialize(appointment)
    {
      id: appointment.id,
      listing_id: appointment.listing_id,
      order_id: appointment.order_id,
      address: appointment.listing.address,
      status: appointment.status,
      request_status: appointment.request_status,
      starts_at: appointment.starts_at,
      ends_at: appointment.ends_at,
      completed_at: appointment.completed_at,
      notes: appointment.notes,
      calendar_color: appointment.calendar_color,
      assigned_user: appointment.assigned_user && appointment.assigned_user.slice(:id, :name, :email, :role),
      team_members: appointment.appointment_team_members.map { |member| serialize_team_member(member) },
      items: appointment.appointment_items.map { |item| item.slice(:id, :order_item_id, :title, :quantity) },
      history: appointment.appointment_events.sort_by(&:created_at).reverse.map do |event|
        event.slice(:id, :event_type, :changeset, :created_at).merge(actor: event.actor&.slice(:id, :name))
      end
    }
  end

  def appointment_scope
    Current.organization.appointments.includes(
      :listing, :assigned_user, :appointment_items,
      appointment_team_members: :user, appointment_events: :actor
    )
  end

  def serialize_team_member(member)
    member.slice(:id, :user_id, :role).merge(user: member.user.slice(:id, :name, :email, :role))
  end

  def record_activity(appointment, event_type)
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: appointment, event_type: event_type)
  end

  def render_schedule_conflict(error)
    raise error unless error.cause.is_a?(PG::ExclusionViolation)

    render json: { error: "schedule_conflict", details: { assigned_user: [ "already has an appointment during this time" ] } }, status: :unprocessable_entity
  end
end
