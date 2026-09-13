module Notifications
  class PrepareDelivery < ApplicationInteractor
    PROCESSING_LEASE = 15.minutes

    def call
      delivery = context.fetch(:delivery)
      context.set(:skip_delivery, false)

      delivery.with_lock do
        if delivery.delivered? || (delivery.processing? && delivery.updated_at > PROCESSING_LEASE.ago)
          context.set(:skip_delivery, true)
          return context
        end

        delivery.update!(status: :processing, attempts: delivery.attempts + 1, last_error: nil)
      end

      context.set(:delivery, delivery)
    end
  end
end
