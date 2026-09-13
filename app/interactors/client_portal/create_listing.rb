module ClientPortal
  # Creates a customer booking request and records the same activity that the
  # portal currently exposes. Account selection and authorization stay in the
  # controller; this action owns the durable mutation.
  class CreateListing < ApplicationInteractor
    def call
      organization = context.fetch(:organization)
      client_account = context.fetch(:client_account)
      actor = context.fetch(:actor)
      attributes = context.fetch(:attributes).to_h.symbolize_keys

      listing = organization.listings.build(
        attributes.merge(client_account:, booked_by: actor, status: :draft, delivery_status: :undelivered)
      )
      listing.save!
      ActivityEvent.create!(organization:, actor:, subject: listing, event_type: "listing.booking_requested")

      context.set(:listing, listing)
    rescue ActiveRecord::RecordInvalid => error
      context.fail!(
        code: "portal_listing_invalid",
        message: error.record.errors.full_messages.to_sentence,
        original_error: error,
        client_account_id: context[:client_account]&.id
      )
    end
  end
end
