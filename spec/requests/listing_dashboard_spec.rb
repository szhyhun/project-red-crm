require "rails_helper"

RSpec.describe "Listing dashboard", type: :request do
  let(:organization) { Organization.create!(name: "Dashboard Agency", slug: "dashboard-agency") }
  let(:manager) { User.create!(organization:, name: "Manager", email: "dashboard@example.test", password: "long-enough-password", role: :manager) }
  let(:client) { ClientAccount.create!(organization:, name: "Taylor Agent", email: "taylor@example.test", kind: :agent) }

  before { sign_in manager }

  it "returns operational counts and combines view with search" do
    scheduled = Listing.create!(organization:, client_account: client, address_line_1: "10 Mason Street")
    unscheduled = Listing.create!(organization:, client_account: client, address_line_1: "20 Oak Street")
    Appointment.create!(organization:, listing: scheduled, starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)

    get "/api/v1/listings", params: { view: "unscheduled", search: "Oak" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("counts")).to include("all" => 2, "unscheduled" => 1)
    expect(response.parsed_body.fetch("listings").pluck("id")).to eq([ unscheduled.id ])
  end

  it "keeps personal saved views private and exposes team views" do
    other = User.create!(organization:, name: "Other", email: "other-dashboard@example.test", password: "long-enough-password", role: :manager)
    SavedListingView.create!(organization:, user: other, name: "Other private", access: :personal)
    SavedListingView.create!(organization:, user: other, name: "Team work", access: :team)
    SavedListingView.create!(organization:, user: manager, name: "Mine", access: :personal)

    get "/api/v1/saved_listing_views"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("saved_views").pluck("name")).to contain_exactly("Team work", "Mine")
  end
end
