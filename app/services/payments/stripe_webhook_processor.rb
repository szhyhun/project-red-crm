module Payments
  class StripeWebhookProcessor
    def initialize(event:)
      @event = event
    end

    def process!
      event_record = PaymentWebhookEvent.create_or_find_by!(provider: "stripe", event_id: @event.id, event_type: @event.type)
      event_record.with_lock do
        return if event_record.processed_at.present?

        payment_intent = @event.data.object
        payment = Payment.find_by(provider: "stripe", provider_payment_id: payment_intent.id)
        process_payment(payment, payment_intent)
        event_record.update!(payment:, processed_at: Time.current)
      end
    end

    private

    def reconcile_success!(payment, payment_intent)
      invoice = payment.invoice
      received_cents = payment_intent.amount_received.to_i
      received_currency = payment_intent.currency.to_s.downcase
      unless received_cents == payment.amount_cents && received_currency == payment.currency.downcase
        payment.update!(status: :failed, provider_payload: ProviderPayload.stripe(payment_intent)) unless payment.succeeded? || payment.refunded?
        return false
      end

      payment_succeeded = false
      Payment.transaction do
        payment.lock!
        invoice.lock!
        unless payment.succeeded?
          payment.update!(status: :succeeded, paid_at: Time.current, provider_payload: ProviderPayload.stripe(payment_intent))
          payment_succeeded = true
          paid_cents = invoice.payments.succeeded.sum(:amount_cents)
          balance_due_cents = [ invoice.total_cents - paid_cents, 0 ].max
          invoice.update!(
            balance_due_cents:,
            status: balance_due_cents.zero? ? :paid : :partially_paid,
            paid_at: balance_due_cents.zero? ? Time.current : nil,
            payment_provider: "stripe"
          )
          invoice.order&.update!(status: :paid) if balance_due_cents.zero? && invoice.order&.status != "cancelled"
          ActivityEvent.create!(organization: invoice.organization, subject: invoice, event_type: "payment.succeeded",
                                payload: { payment_id: payment.id, amount_cents: payment.amount_cents }) if invoice.listing || invoice.order&.listing
          listing = invoice.listing || invoice.order&.listing
          ActivityEvent.create!(organization: invoice.organization, subject: listing, event_type: "payment.succeeded",
                                payload: { payment_id: payment.id, invoice_id: invoice.id, amount_cents: payment.amount_cents }) if listing
        end
      end
      CustomerNotifications.payment_received(payment.reload) if payment_succeeded
      payment_succeeded
    end

    def process_payment(payment, payment_intent)
      return unless payment

      case @event.type
      when "payment_intent.succeeded"
        reconcile_success!(payment, payment_intent)
      when "payment_intent.payment_failed", "payment_intent.canceled"
        payment.update!(status: :failed, provider_payload: ProviderPayload.stripe(payment_intent)) unless payment.succeeded? || payment.refunded?
      end
    end
  end
end
