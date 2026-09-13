module NotificationChannels
  # Sends a browser push notification to each browser a person subscribed.
  # It is switched on by VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY and VAPID_SUBJECT;
  # a subscription the browser has since dropped is forgotten.
  class Push
    def self.configured?
      %w[VAPID_PUBLIC_KEY VAPID_PRIVATE_KEY VAPID_SUBJECT].all? { |key| ENV[key].present? }
    end

    def self.public_key
      ENV["VAPID_PUBLIC_KEY"] if configured?
    end

    def deliver(user:, title:, body:, url:)
      message = { title:, body:, url: }.to_json
      user.push_subscriptions.find_each do |subscription|
        WebPush.payload_send(
          message:, endpoint: subscription.endpoint, p256dh: subscription.p256dh, auth: subscription.auth,
          vapid: { subject: ENV.fetch("VAPID_SUBJECT"), public_key: ENV.fetch("VAPID_PUBLIC_KEY"), private_key: ENV.fetch("VAPID_PRIVATE_KEY") },
          ttl: 24.hours.to_i
        )
        subscription.update_columns(last_delivered_at: Time.current)
      rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
        subscription.destroy
      end
    end
  end
end
