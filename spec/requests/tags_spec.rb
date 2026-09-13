require "rails_helper"

RSpec.describe "Team tags", type: :request do
  let!(:organization) { Organization.create!(name: "Tag agency", slug: "tag-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Tag manager", email: "tag-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:specialist) do
    User.create!(organization:, name: "Tag specialist", email: "tag-specialist@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:vip) { Tag.create!(organization:, name: "VIP", color: "#b91c1c") }
  let!(:coast) { ClientAccount.create!(organization:, name: "Coast", kind: :team) }
  let!(:inland) { ClientAccount.create!(organization:, name: "Inland", kind: :team) }
  let!(:customer) do
    User.create!(organization:, name: "Tag customer", email: "tag-customer@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: coast, user:, role: :admin, status: :active, is_default: true)
    end
  end
  let!(:other_organization) { Organization.create!(name: "Other tag agency", slug: "other-tag-agency") }

  it "does not let production staff or a customer tag a team, and refuses another organization's tag" do
    sign_in specialist
    put "/api/v1/client_accounts/#{coast.id}/tags", params: { client_account: { tag_ids: [ vip.id ] } }
    expect(response).to have_http_status(:forbidden)

    sign_in customer
    get "/api/v1/tags"
    expect(response).to have_http_status(:forbidden)
    get "/api/v1/client_accounts"
    expect(response.parsed_body.fetch("client_accounts").sole.fetch("tags")).to eq([])

    foreign = Tag.create!(organization: other_organization, name: "Foreign")
    sign_in manager
    put "/api/v1/client_accounts/#{coast.id}/tags", params: { client_account: { tag_ids: [ foreign.id ] } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(coast.tags).to be_empty
  end

  it "refuses a duplicate name in any case and a colour that is not hex" do
    sign_in manager

    post "/api/v1/tags", params: { tag: { name: "vip", color: "#000000" } }
    expect(response).to have_http_status(:unprocessable_content)
    post "/api/v1/tags", params: { tag: { name: "Brokerage", color: "red" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "tags a team and filters teams and their people by tag" do
    sign_in manager

    put "/api/v1/client_accounts/#{coast.id}/tags", params: { client_account: { tag_ids: [ vip.id ] } }
    expect(response.parsed_body.fetch("tags")).to eq([ { "id" => vip.id, "name" => "VIP", "color" => "#b91c1c" } ])

    get "/api/v1/client_accounts", params: { tag_id: vip.id }
    expect(response.parsed_body.fetch("client_accounts").map { |row| row["name"] }).to eq([ "Coast" ])

    get "/api/v1/customer_users", params: { tag_id: vip.id }
    expect(response.parsed_body.fetch("customer_users").map { |row| row["email"] }).to eq([ "tag-customer@example.test" ])
    get "/api/v1/customer_users", params: { client_account_id: inland.id }
    expect(response.parsed_body.fetch("customer_users")).to be_empty

    get "/api/v1/tags"
    expect(response.parsed_body.fetch("tags").sole).to include("name" => "VIP", "team_count" => 1)
  end
end
