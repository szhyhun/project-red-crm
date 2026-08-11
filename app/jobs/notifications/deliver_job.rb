module Notifications
  class DeliverJob < ApplicationJob
    PROCESSING_LEASE = 15.minutes

    queue_as :mailers

    def perform(notification_delivery_id)
      delivery = NotificationDelivery.find_by(id: notification_delivery_id)
      return unless delivery

      delivery.with_lock do
        return if delivery.delivered?
        return if delivery.processing? && delivery.updated_at > PROCESSING_LEASE.ago

        delivery.update!(status: :processing, attempts: delivery.attempts + 1, last_error: nil)
      end

      CustomerNotifications.deliver_now(delivery)
      delivery.update!(status: :delivered, delivered_at: Time.current)
    rescue StandardError => error
      delivery&.update(status: :failed, last_error: error.message)
      raise
    end
  end
end
