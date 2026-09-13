module Integrations::Aryeo::Actions::Appointments
  class ImportAppointment < ApplicationInteractor
      def call
        importer = context.fetch(:importer)
        payload = context.fetch(:payload)
        external = importer.appointment_external_id(payload)
        listing = importer.appointment_listing_for(payload)
        return context.set(:appointment, nil) if external.blank? || listing.blank?

        appointment = importer.appointment_record_for(external)
        starts_at = importer.appointment_time_value(payload, "starts_at", "start_at", "scheduled_at", "start_time", "created_at", "updated_at")
        return context.set(:appointment, nil) if starts_at.blank?

        appointment ||= importer.organization.appointments.build(listing:)
        appointment.assign_attributes(
          listing:,
          order: importer.appointment_order_for(payload),
          assigned_user: importer.appointment_staff_for(payload),
          status: importer.appointment_status(payload),
          starts_at:,
          ends_at: importer.appointment_time_value(payload, "ends_at", "end_at", "end_time") || starts_at + 1.hour,
          notes: [ importer.appointment_value(payload, "notes", "description"), "[aryeo:#{external}]" ].compact.join("\n"),
          origin: :aryeo
        )
        appointment.save!

        context.set(:appointment, appointment)
      end
  end
end
