require "rails_helper"

RSpec.describe "Client account team page", type: :request do
  let!(:organization) { Organization.create!(name: "Team page agency", slug: "team-page-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Team page manager", email: "team-page-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:account) { ClientAccount.create!(organization:, name: "Coastal Group", kind: :team, website: "https://coastal.example.test") }
  let!(:lead) { customer("lead", :admin) }
  let!(:partner) { customer("partner", :admin) }
  let!(:assistant) { customer("assistant", :member) }

  def customer(handle, role)
    User.create!(organization:, name: handle.humanize, email: "#{handle}@example.test",
                 password: "long-enough-password", role: role == :admin ? :client_admin : :client_member).tap do |user|
      ClientMembership.create!(client_account: account, user:, role:, status: :active, is_default: true)
    end
  end

  def membership(user) = ClientMembership.find_by!(user:)

  it "does not let a team's own admin archive or split it" do
    sign_in lead

    post "/api/v1/client_accounts/#{account.id}/archive"
    expect(response).to have_http_status(:forbidden)

    post "/api/v1/client_accounts/#{account.id}/split", params: { split: { name: "Breakaway", membership_ids: [ membership(partner).id ] } }
    expect(response).to have_http_status(:forbidden)

    expect(account.reload).not_to be_archived
    expect(ClientAccount.count).to eq(1)
  end

  it "refuses a split that would leave either team without an admin" do
    sign_in manager

    post "/api/v1/client_accounts/#{account.id}/split", params: { split: { name: "Assistants", membership_ids: [ membership(assistant).id ] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig("details", "base").sole).to include("needs an active admin")

    post "/api/v1/client_accounts/#{account.id}/split",
         params: { split: { name: "Everyone", membership_ids: [ lead, partner ].map { |user| membership(user).id } } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig("details", "base").sole).to include("must keep an active admin")

    expect(ClientAccount.count).to eq(1)
  end

  it "refuses to split an agent's own account or an archived team" do
    sign_in manager
    account.update!(kind: :agent)
    post "/api/v1/client_accounts/#{account.id}/split", params: { split: { name: "Nope", membership_ids: [ membership(partner).id ] } }
    expect(response.parsed_body.dig("details", "base").sole).to include("Only a team can be split")

    account.update!(kind: :team, archived_at: Time.current)
    post "/api/v1/client_accounts/#{account.id}/split", params: { split: { name: "Nope", membership_ids: [ membership(partner).id ] } }
    expect(response.parsed_body.dig("details", "base").sole).to include("archived team cannot be split")
    expect(ClientAccount.count).to eq(1)
  end

  it "moves chosen people, and the bill if its member moves, into a new team with the same settings" do
    form = OrderForm.create!(organization:, name: "Coastal form")
    account.update!(billing_user: partner, lock_downloads_before_payment: true, order_form: form,
                    notification_preferences: { "listing_delivered" => { "email" => false } })
    listing = Listing.create!(organization:, client_account: account, address_line_1: "Stays Here Street")
    sign_in manager

    post "/api/v1/client_accounts/#{account.id}/split",
         params: { split: { name: "Partner Group", membership_ids: [ membership(partner).id, membership(assistant).id ] } }

    expect(response).to have_http_status(:created)
    team = ClientAccount.find(response.parsed_body.dig("client_account", "id"))
    expect(team).to have_attributes(name: "Partner Group", kind: "team", website: "https://coastal.example.test",
                                    lock_downloads_before_payment: true, billing_user_id: partner.id, order_form_id: form.id)
    expect(team.notify?("listing_delivered")).to be(false)
    expect(team.client_memberships.map(&:user)).to contain_exactly(partner, assistant)
    expect(account.reload).to have_attributes(billing_user_id: nil)
    expect(account.client_memberships.map(&:user)).to contain_exactly(lead)
    expect(listing.reload.client_account).to eq(account)
  end

  it "archives a team so it takes no new work, and restores it" do
    sign_in manager

    post "/api/v1/client_accounts/#{account.id}/archive"
    expect(response).to have_http_status(:ok)
    expect(account.reload).to be_archived

    listing = Listing.new(organization:, client_account: account, address_line_1: "Too Late Lane")
    expect(listing).not_to be_valid
    expect(listing.errors[:client_account]).to include("is archived")

    delete "/api/v1/client_accounts/#{account.id}/archive"
    expect(account.reload).not_to be_archived
    expect(ActivityEvent.where(subject: account).pluck(:event_type)).to eq(%w[client_account.archived client_account.restored])
  end

  it "counts the team and shows its history to staff but not to a member" do
    Listing.create!(organization:, client_account: account, address_line_1: "Counted Street")
    ClientMembership.create!(client_account: account, role: :member, status: :invited,
                             user: User.create!(organization:, name: "Pending", email: "pending@example.test",
                                                password: "long-enough-password", role: :client_member))
    ActivityEvent.create!(organization:, actor: manager, subject: membership(assistant), event_type: "client_membership.invited",
                          payload: { client_account_id: account.id })

    sign_in assistant
    get "/api/v1/client_accounts/#{account.id}/summary"
    expect(response.parsed_body.fetch("summary")).to include("activity" => [])

    sign_in manager
    get "/api/v1/client_accounts/#{account.id}/summary"
    expect(response.parsed_body.fetch("summary")).to include(
      "listings_count" => 1, "orders_count" => 0, "members_count" => 3, "admins_count" => 2, "invited_count" => 1
    )
    expect(response.parsed_body.dig("summary", "activity").map { |event| event["event_type"] }).to eq([ "client_membership.invited" ])
  end
end
