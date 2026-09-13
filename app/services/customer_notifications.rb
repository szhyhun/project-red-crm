class CustomerNotifications
  class MissingRecipient < StandardError; end

  class << self
    def workspace_welcome(user)
      schedule(kind: "workspace_welcome", notifiable: user, recipients: [ user.email ])
    end

    def invoice_ready(invoice)
      schedule_for_client_account(kind: "invoice_ready", notifiable: invoice, client_account: invoice.client_account, required: true, billing: true)
    end

    def listing_ready(listing)
      listing.customer_accounts.find_each do |client_account|
        schedule_for_client_account(kind: "listing_ready", notifiable: listing, client_account:, delivery: true)
      end
    end

    def feedback_requested(feedback)
      schedule_for_client_account(kind: "feedback_requested", notifiable: feedback, client_account: feedback.client_account)
    end

    def payment_received(payment)
      schedule_for_client_account(kind: "payment_received", notifiable: payment, client_account: payment.invoice.client_account, billing: true)
    end

    def deliver_now(delivery)
      return deliver_sms(delivery) if delivery.by_sms?
      return deliver_push(delivery) if delivery.by_push?

      mailer = case delivery.kind
      when "workspace_welcome" then CustomerMailer.workspace_welcome(delivery.notifiable)
      when "invoice_ready" then CustomerMailer.invoice_ready(delivery.notifiable, recipient: delivery.recipient)
      when "listing_ready" then CustomerMailer.listing_ready(delivery.notifiable, recipient: delivery.recipient)
      when "feedback_requested" then CustomerMailer.feedback_requested(delivery.notifiable, recipient: delivery.recipient)
      when "payment_received" then CustomerMailer.payment_received(delivery.notifiable, recipient: delivery.recipient)
      else raise ArgumentError, "Unknown notification kind: #{delivery.kind}"
      end
      mailer.deliver_now
    end

    # The short form of a notification, for a text message or a push.
    def summary(kind, notifiable)
      case kind
      when "invoice_ready" then [ "Invoice ready", "Invoice #{notifiable.number} from #{notifiable.organization.name} is ready to view." ]
      when "listing_ready" then [ "Media delivered", "#{notifiable.address} is delivered and ready to view." ]
      when "feedback_requested" then [ "How did we do?", "Tell #{notifiable.organization.name} how #{notifiable.listing.address} went." ]
      when "payment_received" then [ "Payment received", "Thank you: payment for invoice #{notifiable.invoice.number} was received." ]
      else raise ArgumentError, "No summary for notification kind: #{kind}"
      end
    end

    private

    TEAM_EVENTS = {
      "invoice_ready" => "payment_required",
      "listing_ready" => "listing_delivered",
      "feedback_requested" => "feedback_requested",
      "payment_received" => "payment_received"
    }.freeze

    # Money goes to the team's billing member when it has one: the rest of the
    # team is not the one being asked to pay. A team that switched an event off
    # on a channel is not told about it there, and a person who switched
    # deliveries off is left out of those alone. SMS and push go out only where
    # they are configured, to people with a phone or a subscribed browser.
    def schedule_for_client_account(kind:, notifiable:, client_account:, required: false, billing: false, delivery: false)
      event = TEAM_EVENTS.fetch(kind)
      people = recipients_for(client_account, billing:, delivery:)

      if client_account.notify?(event, "email")
        emails = (billing && client_account.billing_user.present? ? [] : [ client_account.email ])
        emails = (emails + people.map(&:email)).compact_blank.map(&:downcase).uniq
        raise MissingRecipient, "Add a client email address before sending this notification." if emails.empty? && required

        schedule(kind:, notifiable:, recipients: emails)
      end
      if NotificationChannels::Sms.configured? && client_account.notify?(event, "sms")
        phones = people.filter_map { |person| NotificationChannels::Sms.normalize(person.phone) }.uniq
        schedule(kind:, notifiable:, recipients: phones, channel: "sms")
      end
      if NotificationChannels::Push.configured? && client_account.notify?(event, "push")
        subscribed = people.select { |person| person.push_subscriptions.exists? }
        schedule(kind:, notifiable:, recipients: subscribed.map { |person| "user:#{person.id}" }, channel: "push")
      end
    end

    def recipients_for(client_account, billing:, delivery:)
      return [ client_account.billing_user ] if billing && client_account.billing_user.present?

      memberships = client_account.client_memberships.active.joins(:user).merge(User.active)
      memberships = memberships.where(listing_delivery_notification_enabled: true) if delivery
      User.where(id: memberships.select(:user_id)).to_a
    end

    def schedule(kind:, notifiable:, recipients:, channel: "email")
      recipients.each do |recipient|
        parts = [ kind, notifiable.class.base_class.name, notifiable.id, recipient.downcase ]
        parts.unshift(channel) unless channel == "email"
        key = parts.join(":")
        delivery = NotificationDelivery.create_or_find_by!(deduplication_key: key) do |record|
          record.organization = notifiable.organization
          record.notifiable = notifiable
          record.kind = kind
          record.channel = channel
          record.recipient = recipient.downcase
        end
        next if delivery.delivered?

        begin
          Notifications::DeliverJob.perform_later(delivery.id)
        rescue StandardError => error
          Rails.logger.error("Unable to enqueue notification #{key}: #{error.class}: #{error.message}")
        end
      end
    end

    def deliver_sms(delivery)
      _title, body = summary(delivery.kind, delivery.notifiable)
      NotificationChannels::Sms.new.deliver(to: delivery.recipient, body: "#{body} #{portal_link}")
    end

    def deliver_push(delivery)
      user = User.find(delivery.recipient.delete_prefix("user:"))
      title, body = summary(delivery.kind, delivery.notifiable)
      NotificationChannels::Push.new.deliver(user:, title:, body:, url: portal_link)
    end

    def portal_link
      ENV.fetch("PORTAL_URL", "http://localhost:3011")
    end
  end
end
