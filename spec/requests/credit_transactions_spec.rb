require "rails_helper"

RSpec.describe "Customer credit", type: :request do
  let!(:organization) { Organization.create!(name: "Credit agency", slug: "credit-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Credit manager", email: "credit-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:specialist) do
    User.create!(organization:, name: "Credit specialist", email: "credit-specialist@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:account) { ClientAccount.create!(organization:, name: "Credit Team", kind: :team) }
  let!(:customer) do
    User.create!(organization:, name: "Credit customer", email: "credit-customer@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: account, user:, role: :admin, status: :active, is_default: true)
    end
  end

  def adjust(amount_cents, reason = "Reshoot goodwill")
    post "/api/v1/customer_users/#{customer.id}/credit_transactions",
         params: { credit_transaction: { amount_cents:, reason: } }
  end

  it "does not let a customer or production staff grant credit" do
    # A customer cannot even find people through this endpoint.
    sign_in customer
    adjust(10_000)
    expect(response).to have_http_status(:not_found)

    sign_in specialist
    adjust(10_000)
    expect(response).to have_http_status(:forbidden)

    expect(customer.reload.credit_balance_cents).to eq(0)
    expect(CreditTransaction.count).to eq(0)
  end

  it "no longer lets the balance be overwritten through the profile" do
    sign_in manager

    patch "/api/v1/customer_users/#{customer.id}", params: { customer_user: { credit_balance_cents: 90_000 } }

    expect(customer.reload.credit_balance_cents).to eq(0)
  end

  it "refuses to take the balance below zero, or an adjustment without a reason" do
    sign_in manager

    adjust(-500)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig("details", "base").sole).to include("cannot go below zero")

    adjust(500, "")
    expect(response).to have_http_status(:unprocessable_content)

    expect(customer.reload.credit_balance_cents).to eq(0)
    expect(CreditTransaction.count).to eq(0)
  end

  it "keeps a ledger that explains the balance" do
    sign_in manager

    adjust(10_000)
    expect(response).to have_http_status(:created)
    adjust(-2_500, "Applied to a rush fee")
    expect(response.parsed_body).to include("credit_balance_cents" => 7_500)

    get "/api/v1/customer_users/#{customer.id}/credit_transactions"
    entries = response.parsed_body.fetch("credit_transactions")
    expect(entries.map { |entry| entry.values_at("amount_cents", "balance_after_cents") }).to eq([ [ -2_500, 7_500 ], [ 10_000, 10_000 ] ])
    expect(entries.first.dig("actor", "name")).to eq("Credit manager")
    expect(ActivityEvent.where(subject: customer, event_type: "customer_user.credit_adjusted").count).to eq(2)
  end
end
