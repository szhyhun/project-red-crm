require "rails_helper"

RSpec.describe Payments::StripePaymentIntent do
  it "creates a Stripe PaymentIntent for the server-calculated balance" do
    invoice = create_invoice
    intent = instance_double(Stripe::PaymentIntent, id: "pi_test_4242", client_secret: "pi_test_secret", to_hash: { "payment_method" => "pm_card_visa" })
    allow(Stripe::PaymentIntent).to receive(:create).and_return(intent)

    result = described_class.new(invoice:).create!

    expect(Stripe::PaymentIntent).to have_received(:create).with(
      hash_including(amount: 47_250, currency: "cad", automatic_payment_methods: { enabled: true }),
      hash_including(idempotency_key: "project-red-payment-#{result.payment.id}")
    )
    expect(result.client_secret).to eq("pi_test_secret")
    expect(result.payment).to have_attributes(provider: "stripe", amount_cents: 47_250, provider_payment_id: "pi_test_4242")
  end

  def create_invoice
    organization = Organization.create!(name: "ProjectRed", slug: "projectred")
    client = ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent)
    Invoice.create!(organization:, client_account: client, number: "PR-4242", status: :sent, currency: "cad", total_cents: 47_250, balance_due_cents: 47_250)
  end
end
