require "rails_helper"

RSpec.describe "Customer teams", type: :request do
  let(:organization) { Organization.create!(name: "Team Agency", slug: "team-agency") }
  let(:other_organization) { Organization.create!(name: "Other Team Agency", slug: "other-team-agency") }
  let!(:admin) { User.create!(organization:, name: "Admin", email: "team-admin@example.test", password: "long-enough-password", role: :organization_admin) }

  before { sign_in admin }

  it "creates a team and only accepts client accounts from its organization" do
    post "/api/v1/customer_teams", params: { customer_team: { name: "Oak Bay Realty" } }
    team = organization.customer_teams.find_by!(name: "Oak Bay Realty")
    local_client = organization.client_accounts.create!(name: "Avery Agent")
    outside_client = other_organization.client_accounts.create!(name: "Outside Agent")

    sign_in admin
    post "/api/v1/customer_teams/#{team.id}/memberships", params: { customer_team_membership: { client_account_id: local_client.id, primary: true } }
    expect(response).to have_http_status(:created)

    sign_in admin
    post "/api/v1/customer_teams/#{team.id}/memberships", params: { customer_team_membership: { client_account_id: outside_client.id } }
    expect(response).to have_http_status(:not_found)
  end
end
