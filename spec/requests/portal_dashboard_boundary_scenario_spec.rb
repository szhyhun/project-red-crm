require "rails_helper"

RSpec.describe "Portal dashboard boundary scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Portal boundary agency", slug: "portal-boundary-agency") }
  let!(:other_organization) { Organization.create!(name: "Other portal boundary agency", slug: "other-portal-boundary") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Visible client", kind: :agent) }
  let!(:other_account) { ClientAccount.create!(organization:, name: "Hidden client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Portal customer", email: "portal-boundary@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:manager) do
    User.create!(organization:, name: "Portal manager", email: "portal-boundary-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:own_listing) { Listing.create!(organization:, client_account:, address_line_1: "Own listing") }
  let!(:second_listing) { Listing.create!(organization:, client_account:, address_line_1: "Second own listing") }
  let!(:foreign_listing) { Listing.create!(organization:, client_account: other_account, address_line_1: "Hidden listing") }

  before do
    [ own_listing, second_listing ].each do |listing|
      conversation = Conversation.account_thread_for(organization:, client_account:)
      conversation.conversation_memberships.find_or_create_by!(user: client_user) { |membership| membership.role = :participant }
      conversation.conversation_memberships.find_or_create_by!(user: manager) { |membership| membership.role = :manager }
      conversation.messages.create!(author: manager, body: "Update for #{listing.address_line_1}")
    end
    account_conversation = Conversation.account_thread_for(organization:, client_account: other_account)
    account_conversation.conversation_memberships.create!(user: manager, role: :manager)
    account_conversation.messages.create!(author: manager, body: "Other account update")

    foreign_client = ClientAccount.create!(organization: other_organization, name: "Foreign client", kind: :agent)
    foreign_user = User.create!(organization: other_organization, name: "Foreign user", email: "foreign-portal-boundary@example.test",
                                password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: foreign_client, user: foreign_user, role: :admin)
  end

  it "returns only the signed-in account's listings and account conversation" do
    sign_in client_user

    get "/api/v1/portal/dashboard"

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body

    expect(payload.fetch("client_accounts").pluck("id")).to eq([ client_account.id ])
    expect(payload.fetch("listings").pluck("address")).to contain_exactly("Own listing", "Second own listing")
    expect(payload.fetch("listings").pluck("address")).not_to include("Hidden listing")
    expect(payload.fetch("conversations").pluck("id")).to contain_exactly(
      Conversation.account_thread_for(organization:, client_account:).id
    )
    expect(payload.dig("conversations", 0, "messages").pluck("body")).to include("Update for Own listing", "Update for Second own listing")
  end

  it "keeps a customer from using a same-organization listing id outside its membership" do
    sign_in client_user

    get "/api/v1/portal/listings/#{foreign_listing.id}"

    expect(response).to have_http_status(:not_found)
  end

  it "keeps the portal inaccessible to an internal user" do
    sign_in manager

    get "/api/v1/portal/dashboard"

    expect(response).to have_http_status(:forbidden)
  end
end
