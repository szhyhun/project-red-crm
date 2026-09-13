module Notifications
  class SendDelivery < ApplicationInteractor
    def call
      return context if context.fetch(:skip_delivery)

      delivery = context.fetch(:delivery)
      CustomerNotifications.deliver_now(delivery)
      delivery.update!(status: :delivered, delivered_at: Time.current)
      context.set(:delivery, delivery)
    rescue StandardError => error
      delivery&.update(status: :failed, last_error: error.message)
      context.fail!(code: "notification_delivery_failed", message: error.message,
                    original_error: error, delivery_id: delivery&.id)
    end
  end
end
