require "rails_helper"

RSpec.describe "Client membership lifecycle", type: :request do
  let!(:organization) { Organization.create!(name: "Membership agency", slug: "membership-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Membership manager", email: "membership-manager@example.test",
                 password: "long-enough-password", role: :organization_admin)
  end
  let!(:account) { ClientAccount.create!(organization:, name: "Coast Capital Team", kind: :team) }
  let!(:account_admin) do
    User.create!(organization:, name: "Team admin", email: "team-admin@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: account, user:, role: :admin, status: :active, is_default: true)
    end
  end
  let!(:account_member) do
    User.create!(organization:, name: "Team member", email: "team-member@example.test",
                 password: "long-enough-password", role: :client_member).tap do |user|
      ClientMembership.create!(client_account: account, user:, role: :member, status: :active, is_default: true)
    end
  end
  let!(:other_account) { ClientAccount.create!(organization:, name: "Other team", kind: :team) }
  let!(:outsider) do
    User.create!(organization:, name: "Other team admin", email: "other-team-admin@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: other_account, user:, role: :admin, status: :active, is_default: true)
    end
  end

  def membership_for(user, in_account = account)
    ClientMembership.find_by!(client_account: in_account, user:)
  end

  it "does not let a member invite anyone into their own team" do
    sign_in account_member

    expect {
      post "/api/v1/client_accounts/#{account.id}/memberships", params: {
        client_membership: { email: "newcomer@example.test", name: "Newcomer", role: "member" }
      }
    }.not_to change(ClientMembership, :count)

    expect(response).to have_http_status(:forbidden)
  end

  it "does not let another team's admin see or change this team's memberships" do
    sign_in outsider

    get "/api/v1/client_accounts/#{account.id}/memberships"
    expect(response).to have_http_status(:not_found)

    patch "/api/v1/client_memberships/#{membership_for(account_member).id}", params: {
      client_membership: { role: "admin" }
    }
    expect(response).to have_http_status(:not_found)
    expect(membership_for(account_member).reload).to be_member
  end

  it "does not let a member give themselves a role" do
    sign_in account_member

    patch "/api/v1/client_memberships/#{membership_for(account_member).id}", params: {
      client_membership: { role: "admin" }
    }

    expect(response).to have_http_status(:forbidden)
    expect(membership_for(account_member).reload).to be_member
  end

  it "grants nothing until an invitation is accepted, and everything once it is" do
    sign_in account_admin
    post "/api/v1/client_accounts/#{account.id}/memberships", params: {
      client_membership: { email: "newcomer@example.test", name: "Newcomer", role: "member" }
    }
    expect(response).to have_http_status(:created)

    invited = User.find_by!(email: "newcomer@example.test")
    membership = membership_for(invited)
    expect(membership).to be_invited
    expect(invited.client_accounts).to be_empty
    expect(ClientAccountPolicy::Scope.new(invited, ClientAccount).resolve).to be_empty

    membership.accept!

    expect(membership.reload).to have_attributes(status: "active", is_default: true)
    expect(membership.invitation_accepted_at).to be_present
    expect(invited.reload.client_accounts).to contain_exactly(account)
  end

  it "accepts the invitation when the invited person sets their password" do
    sign_in account_admin
    post "/api/v1/client_accounts/#{account.id}/memberships", params: {
      client_membership: { email: "password-setter@example.test", name: "Password Setter", role: "member" }
    }
    invited = User.find_by!(email: "password-setter@example.test")
    expect(membership_for(invited)).to be_invited

    # Devise stores only the digest of an invitation token, so acceptance goes
    # through the raw token the invitation was sent with, as the form does.
    raw_token = Devise.token_generator.generate(User, :invitation_token).first
    invited.update_columns(invitation_token: Devise.token_generator.digest(User, :invitation_token, raw_token))

    accepted = User.accept_invitation!(invitation_token: raw_token, password: "another-long-password")

    expect(accepted.errors).to be_empty, accepted.errors.full_messages.to_sentence
    expect(membership_for(invited).reload).to be_active
    expect(invited.reload.client_accounts).to contain_exactly(account)
  end

  it "refuses to revoke the last active admin, and allows it once another admin exists" do
    sign_in account_admin

    delete "/api/v1/client_memberships/#{membership_for(account_admin).id}"

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "base")).to include("An account must keep at least one active admin")
    expect(membership_for(account_admin).reload).to be_active

    patch "/api/v1/client_memberships/#{membership_for(account_member).id}", params: {
      client_membership: { role: "admin" }
    }
    expect(response).to have_http_status(:ok)

    delete "/api/v1/client_memberships/#{membership_for(account_admin).id}"
    expect(response).to have_http_status(:ok)
    expect(membership_for(account_admin).reload).to be_revoked
  end

  it "takes access away when a membership is revoked" do
    listing = Listing.create!(organization:, client_account: account, address_line_1: "Revoked Access Street")
    membership = membership_for(account_member)

    expect(ListingPolicy::Scope.new(account_member, Listing).resolve).to include(listing)

    membership.revoke!

    expect(account_member.reload.client_accounts).to be_empty
    expect(ListingPolicy::Scope.new(account_member, Listing).resolve).to be_empty
  end

  it "keeps one landing team per person and hands it on when that team is left" do
    second_membership = ClientMembership.create!(client_account: other_account, user: account_member, role: :member, status: :active)
    sign_in account_member

    patch "/api/v1/client_memberships/#{second_membership.id}", params: { client_membership: { is_default: true } }

    expect(response).to have_http_status(:ok)
    expect(second_membership.reload).to be_is_default
    expect(membership_for(account_member).reload).not_to be_is_default

    second_membership.revoke!

    expect(membership_for(account_member).reload).to be_is_default
  end

  it "lets a person read their own invitations and their own teams" do
    sign_in account_admin
    post "/api/v1/client_accounts/#{account.id}/memberships", params: {
      client_membership: { email: "reader@example.test", name: "Reader", role: "member" }
    }
    invited = User.find_by!(email: "reader@example.test")

    sign_out account_admin
    sign_in invited
    get "/api/v1/portal/memberships"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body.fetch("client_memberships").sole
    expect(body).to include("status" => "invited", "client_account_id" => account.id)
    expect(body.dig("client_account", "name")).to eq("Coast Capital Team")
  end

  it "lets a person turn off delivery notifications for one team only" do
    second_membership = ClientMembership.create!(client_account: other_account, user: account_member, role: :member, status: :active)
    sign_in account_member

    patch "/api/v1/client_memberships/#{second_membership.id}", params: {
      client_membership: { listing_delivery_notification_enabled: false }
    }

    expect(response).to have_http_status(:ok)
    expect(second_membership.reload.listing_delivery_notification_enabled).to be(false)
    expect(membership_for(account_member).reload.listing_delivery_notification_enabled).to be(true)
  end
end
