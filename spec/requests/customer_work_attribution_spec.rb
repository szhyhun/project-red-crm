require "rails_helper"

RSpec.describe "Who placed a team's work", type: :request do
  let!(:organization) { Organization.create!(name: "Attribution agency", slug: "attribution-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Attribution manager", email: "attribution-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:brokerage) { ClientAccount.create!(organization:, name: "Brokerage", kind: :brokerage) }
  let!(:own_team) { ClientAccount.create!(organization:, name: "Own team", kind: :agent) }
  let!(:agent) do
    User.create!(organization:, name: "Two-team agent", email: "two-team@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: brokerage, user:, role: :admin, status: :active)
      ClientMembership.create!(client_account: own_team, user:, role: :admin, status: :active, is_default: true)
    end
  end
  let!(:colleague) do
    User.create!(organization:, name: "Colleague", email: "colleague@example.test",
                 password: "long-enough-password", role: :client_member).tap do |user|
      ClientMembership.create!(client_account: brokerage, user:, role: :member, status: :active, is_default: true)
    end
  end

  def book(params = {})
    post "/api/v1/portal/listings", params: { listing: { address_line_1: "#{SecureRandom.hex(3)} Booking Road", city: "Victoria" }.merge(params) }
  end

  it "refuses to book into a team the customer is not in, or one that is archived" do
    stranger = ClientAccount.create!(organization:, name: "Stranger team", kind: :team)
    sign_in agent

    book(client_account_id: stranger.id)
    expect(response).to have_http_status(:unprocessable_content)

    brokerage.update!(archived_at: Time.current)
    book(client_account_id: brokerage.id)
    expect(response).to have_http_status(:unprocessable_content)
    expect(Listing.count).to eq(0)
  end

  it "books into the team the customer lands in unless they choose another, and records who booked" do
    sign_in agent

    book
    expect(Listing.last).to have_attributes(client_account_id: own_team.id, booked_by_id: agent.id)

    book(client_account_id: brokerage.id)
    expect(Listing.last).to have_attributes(client_account_id: brokerage.id, booked_by_id: agent.id)
  end

  it "shows staff each person's share of a team's work beside the team's" do
    Listing.create!(organization:, client_account: brokerage, address_line_1: "Agent Street", booked_by: agent)
    Listing.create!(organization:, client_account: brokerage, address_line_1: "Colleague Street", booked_by: colleague)
    order = Orders::Create.call(organization:, ordered_by: agent,
                                attributes: { client_account_id: brokerage.id, items: [] }).fetch(:order)
    expect(order.ordered_by).to eq(agent)

    sign_in manager
    get "/api/v1/customer_users/#{agent.id}"
    brokerage_row = response.parsed_body.dig("customer_user", "teams").find { |team| team.dig("client_account", "id") == brokerage.id }
    expect(brokerage_row).to include("listings_count" => 1, "team_listings_count" => 2, "orders_count" => 1, "team_orders_count" => 1)
    expect(brokerage_row.dig("client_account", "member_count")).to eq(2)

    get "/api/v1/customer_users/#{agent.id}/work"
    expect(response.parsed_body.fetch("listings").map { |listing| listing["address"] }).to eq([ "Agent Street" ])
    expect(response.parsed_body.fetch("orders").map { |row| row["id"] }).to eq([ order.id ])
  end

  it "does not show one customer another customer's work" do
    sign_in agent
    get "/api/v1/customer_users/#{colleague.id}/work"

    expect(response).to have_http_status(:not_found)
  end
end
