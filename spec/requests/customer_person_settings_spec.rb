require "rails_helper"

RSpec.describe "A customer person's billing and booking settings", type: :request do
  let!(:organization) { Organization.create!(name: "Person settings agency", slug: "person-settings-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Settings manager", email: "person-settings-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:photographer) do
    User.create!(organization:, name: "Blocked photographer", email: "blocked-photographer@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:other_photographer) do
    User.create!(organization:, name: "Welcome photographer", email: "welcome-photographer@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:team) { ClientAccount.create!(organization:, name: "Settings Team", kind: :team) }
  let!(:customer) do
    User.create!(organization:, name: "Particular customer", email: "particular@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: team, user:, role: :admin, status: :active, is_default: true)
    end
  end
  let!(:imported) do
    User.create!(organization:, name: "Imported customer", email: "imported-settings@example.test",
                 password: "long-enough-password", role: :client_member, origin: "aryeo").tap do |user|
      ClientMembership.create!(client_account: team, user:, role: :member, status: :invited)
    end
  end

  it "does not let a customer block staff or send password resets" do
    sign_in customer

    put "/api/v1/customer_users/#{customer.id}/blocked_staff", params: { staff_ids: [ photographer.id ] }
    expect(response).to have_http_status(:not_found)
    post "/api/v1/customer_users/#{customer.id}/password_reset"
    expect(response).to have_http_status(:not_found)
    expect(CustomerBlockedStaff.count).to eq(0)
  end

  it "refuses to block a customer as if they were staff, and to reset someone who never set a password" do
    sign_in manager

    put "/api/v1/customer_users/#{customer.id}/blocked_staff", params: { staff_ids: [ imported.id ] }
    expect(response).to have_http_status(:unprocessable_content)

    post "/api/v1/customer_users/#{imported.id}/password_reset"
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig("details", "base").sole).to include("invitation")
  end

  it "keeps a billing address, reports verification, and sends a password reset" do
    sign_in manager

    patch "/api/v1/customer_users/#{customer.id}", params: {
      customer_user: { billing_address: { line_1: "1 Billing Way", city: "Victoria", province: "BC", postal_code: "V8V 1A1" } }
    }
    expect(response.parsed_body.dig("customer_user", "billing_address")).to include("line_1" => "1 Billing Way", "city" => "Victoria")
    expect(response.parsed_body.dig("customer_user", "verification_status")).to eq("verified")

    get "/api/v1/customer_users/#{imported.id}"
    expect(response.parsed_body.dig("customer_user", "verification_status")).to eq("unverified")

    expect { post "/api/v1/customer_users/#{customer.id}/password_reset" }.to change(ActionMailer::Base.deliveries, :count).by(1)
    expect(response).to have_http_status(:accepted)
    link = ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{https?://\S+reset_password_token=\S+}]
    token = CGI.unescape(link[/reset_password_token=(\S+)/, 1])

    put "/api/v1/auth/password", params: { reset_password_token: "wrong", password: "brand-new-password", password_confirmation: "brand-new-password" }
    expect(response).to have_http_status(:unprocessable_content)

    put "/api/v1/auth/password", params: { reset_password_token: token, password: "brand-new-password", password_confirmation: "brand-new-password" }
    expect(response).to have_http_status(:ok)
    expect(customer.reload.valid_password?("brand-new-password")).to be(true)
  end

  it "keeps a photographer the customer blocked off the shoots they book" do
    sign_in manager
    put "/api/v1/customer_users/#{customer.id}/blocked_staff", params: { staff_ids: [ photographer.id ] }
    expect(response.parsed_body.dig("customer_user", "blocked_staff")).to eq([ { "id" => photographer.id, "name" => "Blocked photographer" } ])

    listing = Listing.create!(organization:, client_account: team, address_line_1: "Particular Street", booked_by: customer)
    blocked = Appointment.new(organization:, listing:, starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour,
                              assigned_user: photographer)
    expect(blocked).not_to be_valid
    expect(blocked.errors[:assigned_user]).to include("is blocked by this customer")

    appointment = Appointment.create!(organization:, listing:, starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour,
                                      assigned_user: other_photographer)
    expect(appointment.appointment_team_members.build(user: photographer)).not_to be_valid
  end
end
