require "rails_helper"

RSpec.describe "Customer users", type: :request do
  let!(:organization) { Organization.create!(name: "People agency", slug: "people-agency") }
  let!(:manager) do
    User.create!(organization:, name: "People manager", email: "people-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:specialist) do
    User.create!(organization:, name: "People specialist", email: "people-specialist@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:account) { ClientAccount.create!(organization:, name: "People Team", kind: :team) }
  let!(:customer) do
    User.create!(organization:, name: "Aaron Hambley", email: "aaron@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: account, user:, role: :admin, status: :active, is_default: true)
    end
  end
  let!(:other_organization) { Organization.create!(name: "Other people agency", slug: "other-people-agency") }
  let!(:foreign_customer) do
    User.create!(organization: other_organization, name: "Foreign customer", email: "foreign-customer@example.test",
                 password: "long-enough-password", role: :client_member)
  end

  it "does not let a customer read the customer list" do
    sign_in customer

    get "/api/v1/customer_users"

    expect(response).to have_http_status(:forbidden)
  end

  it "does not let production staff change a customer" do
    sign_in specialist

    patch "/api/v1/customer_users/#{customer.id}", params: { customer_user: { blocked_from_ordering: true } }

    expect(response).to have_http_status(:forbidden)
    expect(customer.reload.blocked_from_ordering).to be(false)
  end

  it "does not reach a customer in another organization, or a staff member through this endpoint" do
    sign_in manager

    get "/api/v1/customer_users/#{foreign_customer.id}"
    expect(response).to have_http_status(:not_found)

    get "/api/v1/customer_users/#{specialist.id}"
    expect(response).to have_http_status(:not_found)
  end

  it "lists customers with their teams and edits a person's standing" do
    sign_in manager

    get "/api/v1/customer_users"
    listed = response.parsed_body.fetch("customer_users").sole
    expect(listed).to include("email" => "aaron@example.test", "team_count" => 1)
    expect(listed.fetch("capabilities")).to include("update")
    expect(listed.dig("teams", 0, "client_account", "name")).to eq("People Team")

    patch "/api/v1/customer_users/#{customer.id}", params: {
      customer_user: {
        phone: "250-858-8697", license_number: "BC-1234", internal_note: "Prefers morning shoots",
        blocked_from_ordering: true, credit_balance_cents: 5_000, social_profiles: { instagram: "@hambley" }
      }
    }

    expect(response).to have_http_status(:ok)
    expect(customer.reload).to have_attributes(
      phone: "250-858-8697", license_number: "BC-1234", blocked_from_ordering: true, credit_balance_cents: 5_000
    )
    expect(customer.social_profiles).to eq("instagram" => "@hambley")
    expect(ActivityEvent.where(subject: customer, event_type: "customer_user.updated")).to exist
  end
end
