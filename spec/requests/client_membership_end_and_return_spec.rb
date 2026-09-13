require "rails_helper"

RSpec.describe "Archiving, reactivating and deleting a membership", type: :request do
  let!(:organization) { Organization.create!(name: "Return agency", slug: "return-agency") }
  let!(:team) { ClientAccount.create!(organization:, name: "Return Team", kind: :team) }
  let!(:admin) { customer("return-admin", :admin, :active) }
  let!(:member) { customer("return-member", :member, :active) }

  def customer(handle, role, status)
    User.create!(organization:, name: handle.humanize, email: "#{handle}@example.test", password: "long-enough-password",
                 role: role == :admin ? :client_admin : :client_member).tap do |user|
      ClientMembership.create!(client_account: team, user:, role:, status:, invitation_accepted_at: Time.current)
    end
  end

  def membership(user) = ClientMembership.find_by!(user:)

  it "does not let a member end or delete someone's membership" do
    sign_in member

    post "/api/v1/client_memberships/#{membership(admin).id}/archive"
    expect(response).to have_http_status(:forbidden)
    delete "/api/v1/client_memberships/#{membership(admin).id}/purge"
    expect(response).to have_http_status(:forbidden)
    expect(membership(admin)).to be_active
  end

  it "refuses to reactivate a live membership or delete one that has not ended" do
    sign_in admin

    post "/api/v1/client_memberships/#{membership(member).id}/reactivate"
    expect(response).to have_http_status(:unprocessable_content)
    delete "/api/v1/client_memberships/#{membership(member).id}/purge"
    expect(response).to have_http_status(:unprocessable_content)
    expect(ClientMembership.count).to eq(2)
  end

  it "archives, brings back and finally deletes a membership, keeping its history" do
    sign_in admin
    id = membership(member).id

    post "/api/v1/client_memberships/#{id}/archive"
    expect(response.parsed_body.dig("client_membership", "status")).to eq("archived")
    post "/api/v1/client_memberships/#{id}/reactivate"
    expect(response.parsed_body.dig("client_membership", "status")).to eq("active")
    delete "/api/v1/client_memberships/#{id}"
    delete "/api/v1/client_memberships/#{id}/purge"
    expect(response).to have_http_status(:no_content)

    expect(ClientMembership.exists?(id)).to be(false)
    expect(ActivityEvent.where("event_type LIKE 'client_membership.%'").where(actor: admin).pluck(:event_type))
      .to include("client_membership.archived", "client_membership.reactivated", "client_membership.revoked", "client_membership.deleted")
  end
end
