require "rails_helper"

RSpec.describe Payments::StripeWebhookProcessor do
  it "marks the invoice paid once and queues a receipt" do
    payment = create_payment
    event = stripe_event("payment_intent.succeeded", amount_received: payment.amount_cents, currency: payment.currency)

    expect { described_class.new(event:).process! }
      .to change(NotificationDelivery, :count).by(1)
      .and have_enqueued_job(Notifications::DeliverJob).on_queue("mailers")
    expect(payment.reload).to be_succeeded
    expect(payment.invoice.reload).to have_attributes(status: "paid", balance_due_cents: 0)
    expect { described_class.new(event:).process! }.not_to change(NotificationDelivery, :count)
  end


  it "does not regress a succeeded payment when a delayed failure arrives" do
    payment = create_payment
    described_class.new(event: stripe_event("payment_intent.succeeded", amount_received: payment.amount_cents, currency: payment.currency)).process!

    described_class.new(event: stripe_event("payment_intent.payment_failed", amount_received: 0, currency: payment.currency)).process!

    expect(payment.reload).to be_succeeded
    expect(payment.invoice.reload).to be_paid
  end

  it "does not credit a mismatched provider amount" do
    payment = create_payment
    described_class.new(event: stripe_event("payment_intent.succeeded", amount_received: 42, currency: payment.currency)).process!
    expect(payment.reload).to be_failed
    expect(payment.invoice.reload).to have_attributes(status: "sent", balance_due_cents: 47_250)
  end

  def create_payment
    organization = Organization.create!(name: "ProjectRed", slug: "projectred")
    client = ClientAccount.create!(organization:, name: "Avery Agent", email: "avery@example.test", kind: :agent)
    invoice = Invoice.create!(organization:, client_account: client, number: "PR-4242", status: :sent, currency: "cad", total_cents: 47_250, balance_due_cents: 47_250)
    Payment.create!(organization:, invoice:, provider: "stripe", provider_payment_id: "pi_test_4242", status: :pending, amount_cents: 47_250, currency: "cad")
  end

  def stripe_event(type, amount_received:, currency:)
    intent = Struct.new(:id, :amount_received, :currency) do
      def to_hash = { "id" => id, "amount_received" => amount_received, "currency" => currency }
    end.new("pi_test_4242", amount_received, currency)
    Struct.new(:type, :data).new(type, Struct.new(:object).new(intent))
  end
end
