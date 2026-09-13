require "rails_helper"

RSpec.describe "Client account billing and visibility", type: :request do
  let!(:organization) { Organization.create!(name: "Billing agency", slug: "billing-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Billing manager", email: "billing-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:account) { ClientAccount.create!(organization:, name: "Billing Team", kind: :team) }
  let!(:team_admin) { customer("team-admin", :admin) }
  let!(:team_member) { customer("team-member", :member) }
  let!(:outsider) do
    User.create!(organization:, name: "Outsider", email: "outsider@example.test",
                 password: "long-enough-password", role: :client_member)
  end
  let!(:listing) { Listing.create!(organization:, client_account: account, address_line_1: "Billing Street") }
  let!(:invoice) do
    Invoice.create!(organization:, client_account: account, listing:, number: "INV-BILL-1", status: :sent,
                    due_on: Date.current + 7, subtotal_cents: 20_000, total_cents: 20_000, balance_due_cents: 20_000)
  end

  def customer(handle, role)
    User.create!(organization:, name: handle.humanize, email: "#{handle}@example.test",
                 password: "long-enough-password", role: role == :admin ? :client_admin : :client_member).tap do |user|
      ClientMembership.create!(client_account: account, user:, role:, status: :active, is_default: true)
    end
  end

  def portal_invoices
    get "/api/v1/portal/listings"
    response.parsed_body.fetch("listings").sole.fetch("invoices")
  end

  it "does not let a team's own admin decide who pays or what the team sees" do
    sign_in team_admin

    patch "/api/v1/client_accounts/#{account.id}/billing", params: {
      client_account: { billing_user_id: team_admin.id, billing_visibility: "hidden" }
    }

    expect(response).to have_http_status(:forbidden)
    expect(account.reload).to have_attributes(billing_user_id: nil, billing_visibility: "everyone")
  end

  it "refuses a billing member who is not in the team" do
    sign_in manager

    patch "/api/v1/client_accounts/#{account.id}/billing", params: { client_account: { billing_user_id: outsider.id } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig("details", "billing_user")).to include("must be an active admin of this team")
    expect(account.reload.billing_user_id).to be_nil
  end

  it "makes the billing member an admin, keeps them one, and asks only them to pay" do
    sign_in manager
    patch "/api/v1/client_accounts/#{account.id}/billing", params: { client_account: { billing_user_id: team_member.id } }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("client_account", "billing_user", "email")).to eq("team-member@example.test")
    expect(response.parsed_body.dig("client_account", "capabilities")).to include("configure_billing")
    membership = account.client_memberships.find_by!(user: team_member)
    expect(membership).to be_admin
    expect(ActivityEvent.where(subject: account, event_type: "client_account.billing_configured")).to exist

    # Even the team's other admin cannot quietly drop the person the bill goes to.
    sign_in team_admin
    patch "/api/v1/client_memberships/#{membership.id}", params: { client_membership: { role: "member" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(membership.reload).to be_admin

    CustomerNotifications.invoice_ready(invoice.reload)
    expect(NotificationDelivery.where(kind: "invoice_ready").pluck(:recipient)).to eq([ "team-member@example.test" ])

    expect(portal_invoices.sole.fetch("can_pay")).to be(false)

    sign_in team_member
    expect(portal_invoices.sole.fetch("can_pay")).to be(true)
  end

  it "asks nobody to pay online when the team settles outside the system" do
    account.update!(billing_user: team_admin, billing_pays_externally: true)
    sign_in team_admin

    expect(portal_invoices.sole.fetch("can_pay")).to be(false)
  end

  it "shows billing only to the people the switch allows" do
    account.update!(billing_visibility: "admins")

    sign_in team_member
    expect(portal_invoices).to be_empty
    get "/api/v1/invoices"
    expect(response.parsed_body.fetch("invoices")).to be_empty
    get "/api/v1/portal/dashboard"
    expect(response.parsed_body.dig("client_accounts", 0, "visible_blocks")).not_to include("billing")

    sign_in team_admin
    expect(portal_invoices.size).to eq(1)

    account.update!(billing_visibility: "hidden", pricing_visibility: "everyone")
    expect(portal_invoices).to be_empty
    get "/api/v1/portal/dashboard"
    expect(response.parsed_body.dig("client_accounts", 0, "visible_blocks")).to eq([ "pricing" ])
  end
end
