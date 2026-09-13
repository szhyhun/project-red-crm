module ClientPortal
  # Records a customer's reschedule request as one appointment/activity
  # transition. The controller remains responsible for access and HTTP-window
  # validation because those decisions depend on the signed-in customer.
  class RequestReschedule < ApplicationInteractor
    def call
      appointment = context.fetch(:appointment)
      actor = context.fetch(:actor)
      starts_at = context.fetch(:starts_at)
      ends_at = context.fetch(:ends_at)
      notes = context[:notes].to_s.presence

      Appointment.transaction do
        appointment.update!(request_status: :requested)
        appointment.appointment_events.create!(
          actor:,
          event_type: "customer_reschedule_requested",
          changeset: {
            "starts_at" => starts_at.iso8601,
            "ends_at" => ends_at.iso8601,
            "notes" => notes
          }.compact
        )
        ActivityEvent.create!(
          organization: appointment.listing.organization,
          actor:,
          subject: appointment.listing,
          event_type: "appointment.customer_reschedule_requested",
          payload: { appointment_id: appointment.id, starts_at: starts_at.iso8601, ends_at: ends_at.iso8601 }
        )
      end

      context.set(:appointment, appointment.reload)
    rescue ActiveRecord::RecordInvalid => error
      context.fail!(
        code: "appointment_reschedule_invalid",
        message: error.record.errors.full_messages.to_sentence,
        original_error: error,
        appointment_id: context[:appointment]&.id
      )
    end
  end
end
