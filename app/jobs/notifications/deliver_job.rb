module Notifications
  class DeliverJob < ApplicationJob
    queue_as :mailers

    def perform(notification_delivery_id)
      delivery = NotificationDelivery.find_by(id: notification_delivery_id)
      return unless delivery

      result = Deliver.call(delivery:)
      raise result.failure.original_error || result.failure if result.failure?
    end
  end
end
