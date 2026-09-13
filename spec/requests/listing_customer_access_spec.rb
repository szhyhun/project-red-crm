require "rails_helper"

RSpec.describe "Which of a team's people see a listing", type: :request do
  let!(:organization) { Organization.create!(name: "Access agency", slug: "access-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Access manager", email: "access-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:team) { ClientAccount.create!(organization:, name: "Access Team", kind: :team, member_listing_access: "attached_listings") }
  let!(:admin) { customer("access-admin", :admin) }
  let!(:booker) { customer("access-booker", :member) }
  let!(:given) { customer("access-given", :member) }
  let!(:bystander) { customer("access-bystander", :member) }
  let!(:listing) { Listing.create!(organization:, client_account: team, address_line_1: "Access Street", booked_by: booker) }
  let!(:other_team) { ClientAccount.create!(organization:, name: "Other access team", kind: :team) }

  def customer(handle, role)
    User.create!(organization:, name: handle.humanize, email: "#{handle}@example.test", password: "long-enough-password",
                 role: role == :admin ? :client_admin : :client_member).tap do |user|
      ClientMembership.create!(client_account: team, user:, role:, status: :active)
    end
  end

  def membership(user) = ClientMembership.find_by!(user:, client_account: team)

  def listing_ids_for(user)
    sign_in user
    get "/api/v1/portal/listings"
    response.parsed_body.fetch("listings").map { |row| row["id"] }
  end

  it "does not let a member share a listing, or anyone share it with another team's people" do
    sign_in booker
    put "/api/v1/listings/#{listing.id}/customer_access", params: { customer_access: { membership_ids: [ membership(bystander).id ] } }
    expect(response).to have_http_status(:forbidden)

    outsider = User.create!(organization:, name: "Outsider", email: "access-outsider@example.test",
                            password: "long-enough-password", role: :client_member)
    foreign = ClientMembership.create!(client_account: other_team, user: outsider, role: :member, status: :active)
    sign_in admin
    put "/api/v1/listings/#{listing.id}/customer_access", params: { customer_access: { membership_ids: [ foreign.id ] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(ListingMembership.count).to eq(0)
  end

  it "shows a team that keeps listings to their people only the listings they booked or were given" do
    expect(listing_ids_for(bystander)).to be_empty
    get "/api/v1/portal/listings/#{listing.id}"
    expect(response).to have_http_status(:not_found)

    expect(listing_ids_for(booker)).to eq([ listing.id ])
    expect(listing_ids_for(admin)).to eq([ listing.id ])

    put "/api/v1/listings/#{listing.id}/customer_access", params: { customer_access: { membership_ids: [ membership(given).id ] } }
    expect(response).to have_http_status(:ok)
    rows = response.parsed_body.dig("customer_access", "memberships").index_by { |row| row.dig("user", "email") }
    expect(rows.transform_values { |row| row["sees_listing"] }).to include(
      "access-given@example.test" => true, "access-bystander@example.test" => false, "access-booker@example.test" => true
    )

    expect(listing_ids_for(given)).to eq([ listing.id ])
    expect(listing_ids_for(bystander)).to be_empty
  end

  it "shows every member all of a team's listings when the team shares them, as before" do
    team.update!(member_listing_access: "all_team_listings")

    expect(listing_ids_for(bystander)).to eq([ listing.id ])
  end

  it "keeps a member's orders on hidden listings out of reach, but not the ones they placed" do
    hidden_order = Order.create!(organization:, client_account: team, listing:)
    own_order = Order.create!(organization:, client_account: team, ordered_by: bystander)
    sign_in bystander

    get "/api/v1/orders"
    expect(response.parsed_body.fetch("orders").map { |row| row["id"] }).to eq([ own_order.id ])
    get "/api/v1/orders/#{hidden_order.id}"
    expect(response).to have_http_status(:not_found)
  end
end
