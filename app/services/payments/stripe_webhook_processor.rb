module Payments
  class StripeWebhookProcessor
    def initialize(event:)
      @event = event
    end

    def process!
      payment_intent = @event.data.object
      payment = Payment.find_by(provider: "stripe", provider_payment_id: payment_intent.id)
      return unless payment

      case @event.type
      when "payment_intent.succeeded"
        reconcile_success!(payment, payment_intent)
      when "payment_intent.payment_failed", "payment_intent.canceled"
        payment.update!(status: :failed, provider_payload: payment_intent.to_hash) unless payment.succeeded? || payment.refunded?
      end
    end

    private

    def reconcile_success!(payment, payment_intent)
      invoice = payment.invoice
      received_cents = payment_intent.amount_received.to_i
      received_currency = payment_intent.currency.to_s.downcase
      unless received_cents == payment.amount_cents && received_currency == payment.currency.downcase
        payment.update!(status: :failed, provider_payload: payment_intent.to_hash)
        return
      end

      Payment.transaction do
        payment.lock!
        invoice.lock!
        unless payment.succeeded?
          payment.update!(status: :succeeded, paid_at: Time.current, provider_payload: payment_intent.to_hash)
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
      CustomerNotifications.payment_received(payment.reload)
    end
  end
end
