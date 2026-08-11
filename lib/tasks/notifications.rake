namespace :notifications do
  desc "Enqueue pending or failed notification deliveries"
  task dispatch_pending: :environment do
    ready = NotificationDelivery.where(status: %i[pending failed])
    stale = NotificationDelivery.processing.where(updated_at: ...Notifications::DeliverJob::PROCESSING_LEASE.ago)

    ready.or(stale).find_each do |delivery|
      Notifications::DeliverJob.perform_later(delivery.id)
    end
  end
end
