require "rails_helper"

RSpec.describe Aryeo::PayloadSanitizer do
  it "redacts payment credentials while retaining safe financial history" do
    payload = described_class.call(
      "amount" => 549,
      "card_number" => "4242424242424242",
      "payment_token" => "tok_secret",
      "nested" => { "routing_number" => "123456789" }
    )

    expect(payload).to include("amount" => 549, "card_number" => "[REDACTED]", "payment_token" => "[REDACTED]")
    expect(payload.dig("nested", "routing_number")).to eq("[REDACTED]")
  end
end
