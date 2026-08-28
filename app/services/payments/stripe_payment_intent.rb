module Payments
  class StripePaymentIntent
    class PaymentUnavailable < StandardError; end

    Result = Data.define(:payment, :client_secret)

    def initialize(invoice:)
      @invoice = invoice
    end

    def create!
      raise PaymentUnavailable, "This invoice has no balance due" unless @invoice.balance_due_cents.positive?
      raise PaymentUnavailable, "This invoice cannot be paid online" if @invoice.draft? || @invoice.void?

      @invoice.with_lock do
        payment = @invoice.payments.pending.where(provider: "stripe").order(created_at: :desc).first
        payment, intent = payment&.provider_payment_id.present? ? [ payment, retrieve(payment) ] : create_intent(payment)

        Result.new(payment:, client_secret: intent.client_secret)
      end
    end

    private

    def create_intent(existing_payment)
      payment = existing_payment || @invoice.payments.create!(
        organization: @invoice.organization,
        provider: "stripe",
        status: :pending,
        amount_cents: @invoice.balance_due_cents,
        currency: @invoice.currency
      )

      intent = Stripe::PaymentIntent.create(
        {
          amount: payment.amount_cents,
          currency: payment.currency,
          automatic_payment_methods: { enabled: true },
          metadata: { invoice_id: @invoice.id, organization_id: @invoice.organization_id, payment_id: payment.id }
        },
        { idempotency_key: "project-red-payment-#{payment.id}" }
      )

      payment.update!(provider_payment_id: intent.id, provider_payload: intent.to_hash)
      [ payment, intent ]
    end

    def retrieve(payment)
      Stripe::PaymentIntent.retrieve(payment.provider_payment_id)
    end
  end
end
