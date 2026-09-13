require "rails_helper"

RSpec.describe "Joining a team by affiliate code", type: :request do
  let!(:organization) { Organization.create!(name: "Affiliate agency", slug: "affiliate-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Affiliate manager", email: "affiliate-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:team) { ClientAccount.create!(organization:, name: "Coast Team", kind: :team, affiliate_id: "COAST") }
  let!(:own_team) { ClientAccount.create!(organization:, name: "Solo agent", kind: :agent) }
  let!(:agent) do
    User.create!(organization:, name: "Solo agent", email: "solo-agent@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: own_team, user:, role: :admin, status: :active, is_default: true)
    end
  end
  let!(:other_organization) { Organization.create!(name: "Other affiliate agency", slug: "other-affiliate-agency") }

  def join(code)
    post "/api/v1/portal/team_joins", params: { affiliate_id: code }
  end

  it "does not let staff join a customer team by code" do
    sign_in manager
    join("COAST")

    expect(response).to have_http_status(:forbidden)
    expect(team.client_memberships).to be_empty
  end

  it "refuses an unknown code, another organization's code, an archived team, and a removed member" do
    ClientAccount.create!(organization: other_organization, name: "Elsewhere", kind: :team, affiliate_id: "ELSEWHERE")
    sign_in agent

    join("NOPE")
    expect(response).to have_http_status(:unprocessable_content)
    join("ELSEWHERE")
    expect(response).to have_http_status(:unprocessable_content)

    team.update!(archived_at: Time.current)
    join("COAST")
    expect(response).to have_http_status(:unprocessable_content)
    team.update!(archived_at: nil)

    ClientMembership.create!(client_account: team, user: agent, role: :member, status: :revoked)
    join("coast")
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig("details", "base").sole).to include("invite you back")
    expect(team.client_memberships.sole).to be_revoked
  end

  it "joins the team as a member, whatever the code's case, without moving where they land" do
    sign_in agent

    join(" coast ")

    expect(response).to have_http_status(:created)
    membership = team.client_memberships.find_by!(user: agent)
    expect(membership).to have_attributes(role: "member", status: "active", is_default: false)
    expect(agent.reload.client_account_ids).to contain_exactly(own_team.id, team.id)
    expect(ActivityEvent.where(subject: membership, event_type: "client_membership.joined_by_affiliate_code")).to exist

    join("COAST")
    expect(response).to have_http_status(:created)
    expect(ActivityEvent.where(event_type: "client_membership.joined_by_affiliate_code").count).to eq(1)
  end
end
