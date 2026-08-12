class CustomerNotifications
  class MissingRecipient < StandardError; end

  class << self
    def workspace_welcome(user)
      schedule(kind: "workspace_welcome", notifiable: user, recipients: [user.email])
    end

    def invoice_ready(invoice)
      schedule_for_client_account(kind: "invoice_ready", notifiable: invoice, client_account: invoice.client_account, required: true)
    end

    def listing_ready(listing)
      listing.customer_accounts.find_each do |client_account|
        schedule_for_client_account(kind: "listing_ready", notifiable: listing, client_account:)
      end
    end

    def feedback_requested(feedback)
      schedule_for_client_account(kind: "feedback_requested", notifiable: feedback, client_account: feedback.client_account)
    end

    def payment_received(payment)
      schedule_for_client_account(kind: "payment_received", notifiable: payment, client_account: payment.invoice.client_account)
    end

    def deliver_now(delivery)
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

    private

    def schedule_for_client_account(kind:, notifiable:, client_account:, required: false)
      recipients = [client_account.email, *client_account.users.active.pluck(:email)].compact_blank.map(&:downcase).uniq
      raise MissingRecipient, "Add a client email address before sending this notification." if recipients.empty? && required

      schedule(kind:, notifiable:, recipients:)
    end

    def schedule(kind:, notifiable:, recipients:)
      recipients.each do |recipient|
        key = [kind, notifiable.class.base_class.name, notifiable.id, recipient.downcase].join(":")
        delivery = NotificationDelivery.create_or_find_by!(deduplication_key: key) do |record|
          record.organization = notifiable.organization
          record.notifiable = notifiable
          record.kind = kind
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
  end
end
