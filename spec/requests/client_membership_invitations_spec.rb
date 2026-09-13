require "rails_helper"

RSpec.describe "Client membership invitations", type: :request do
  let!(:organization) { Organization.create!(name: "Invitation agency", slug: "invitation-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Invitation admin", email: "invitation-admin@example.test",
                 password: "long-enough-password", role: :organization_admin)
  end
  let!(:account) { ClientAccount.create!(organization:, name: "Imported Team", kind: :team) }
  let!(:team_admin) do
    User.create!(organization:, name: "Imported admin", email: "imported-admin@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: account, user:, role: :admin, status: :active, is_default: true)
    end
  end
  let!(:team_member) do
    User.create!(organization:, name: "Active member", email: "active-member@example.test",
                 password: "long-enough-password", role: :client_member).tap do |user|
      ClientMembership.create!(client_account: account, user:, role: :member, status: :active)
    end
  end
  let!(:imported) do
    User.create!(organization:, name: "Imported person", email: "imported-person@example.test",
                 password: "long-enough-password", role: :client_member, origin: "aryeo").tap do |user|
      ClientMembership.create!(client_account: account, user:, role: :member, status: :invited)
    end
  end
  let(:imported_membership) { ClientMembership.find_by!(user: imported) }

  it "does not let a plain member send invitations for their team" do
    sign_in team_member

    expect { post "/api/v1/client_memberships/#{imported_membership.id}/invitation" }
      .not_to change(ActionMailer::Base.deliveries, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "refuses to email someone whose membership is already active, or who already signs in" do
    sign_in manager

    post "/api/v1/client_memberships/#{ClientMembership.find_by!(user: team_member).id}/invitation"
    expect(response).to have_http_status(:unprocessable_content)

    other_team = ClientAccount.create!(organization:, name: "Second team", kind: :team)
    pending = ClientMembership.create!(client_account: other_team, user: team_member, role: :member, status: :invited)
    post "/api/v1/client_memberships/#{pending.id}/invitation"
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.dig("details", "base").sole).to include("already signs in")
  end

  it "emails an imported person the invitation that gives them access" do
    sign_in team_admin

    expect { post "/api/v1/client_memberships/#{imported_membership.id}/invitation" }
      .to change(ActionMailer::Base.deliveries, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(ActionMailer::Base.deliveries.last.to).to eq([ "imported-person@example.test" ])
    expect(imported.reload.invitation_sent_at).to be_present
    expect(ActivityEvent.where(subject: imported_membership, event_type: "client_membership.invitation_sent")).to exist
  end
end
