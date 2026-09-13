require "rails_helper"

RSpec.describe "Client account notifications", type: :request do
  let!(:organization) { Organization.create!(name: "Notice agency", slug: "notice-agency") }
  let!(:account) { ClientAccount.create!(organization:, name: "Notice Team", kind: :team) }
  let!(:team_admin) { customer("notice-admin", :admin) }
  let!(:team_member) { customer("notice-member", :member) }
  # A listing lists its own account among its customers.
  let!(:listing) { Listing.create!(organization:, client_account: account, address_line_1: "Notice Street") }

  def customer(handle, role)
    User.create!(organization:, name: handle.humanize, email: "#{handle}@example.test",
                 password: "long-enough-password", role: role == :admin ? :client_admin : :client_member).tap do |user|
      ClientMembership.create!(client_account: account, user:, role:, status: :active, is_default: true)
    end
  end

  def listing_ready_recipients
    NotificationDelivery.where(kind: "listing_ready").pluck(:recipient)
  end

  it "does not let a member change what the team is told about" do
    sign_in team_member

    patch "/api/v1/client_accounts/#{account.id}/notifications",
          params: { client_account: { notification_preferences: { listing_delivered: { email: false } } } }

    expect(response).to have_http_status(:forbidden)
    expect(account.reload.notify?("listing_delivered")).to be(true)
  end

  it "refuses events and channels it does not know" do
    sign_in team_admin

    patch "/api/v1/client_accounts/#{account.id}/notifications",
          params: { client_account: { notification_preferences: { fax_blast: { carrier_pigeon: false } } } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(account.reload.notification_preferences).to eq({})
  end

  it "lets a team admin switch an event off, and stops those emails to the team" do
    sign_in team_admin

    get "/api/v1/client_accounts/#{account.id}/notifications"
    expect(response.parsed_body.dig("notifications", "matrix", "listing_delivered")).to eq("email" => true, "sms" => true, "push" => true)

    patch "/api/v1/client_accounts/#{account.id}/notifications",
          params: { client_account: { notification_preferences: { listing_delivered: { email: false, sms: false } } } }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("notifications", "matrix", "listing_delivered")).to eq("email" => false, "sms" => false, "push" => true)

    CustomerNotifications.listing_ready(listing)
    expect(listing_ready_recipients).to be_empty
  end

  it "leaves out a person who switched deliveries off, and anyone still only invited" do
    ClientMembership.find_by!(user: team_member).update!(listing_delivery_notification_enabled: false)
    invited = User.create!(organization:, name: "Invited", email: "notice-invited@example.test",
                           password: "long-enough-password", role: :client_member)
    ClientMembership.create!(client_account: account, user: invited, role: :member, status: :invited)

    CustomerNotifications.listing_ready(listing)

    expect(listing_ready_recipients).to eq([ "notice-admin@example.test" ])
  end
end
