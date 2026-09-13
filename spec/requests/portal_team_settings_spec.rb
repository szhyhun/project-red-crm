require "rails_helper"

RSpec.describe "The team settings a customer may read", type: :request do
  let!(:organization) { Organization.create!(name: "Readable agency", slug: "readable-agency") }
  let!(:team) do
    ClientAccount.create!(organization:, name: "Readable Team", kind: :team, lock_downloads_before_payment: true,
                          billing_visibility: "admins", pricing_visibility: "everyone", downloads_visibility: "hidden",
                          marketing_templates_visibility: "admins")
  end
  let!(:admin) { customer("readable-admin", :admin) }
  let!(:member) { customer("readable-member", :member) }
  let!(:product) do
    Product.create!(organization:, slug: "readable-photos", title: "Photos", kind: :service).tap do |record|
      record.product_variants.create!(title: "Standard", price_cents: 30_000)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account: team, address_line_1: "Readable Street") }
  let!(:material) { MarketingMaterial.create!(organization:, listing:, material_type: :flyer, title: "Open house flyer", status: :ready) }

  def customer(handle, role)
    User.create!(organization:, name: handle.humanize, email: "#{handle}@example.test", password: "long-enough-password",
                 role: role == :admin ? :client_admin : :client_member).tap do |user|
      ClientMembership.create!(client_account: team, user:, role:, status: :active, is_default: true)
    end
  end

  def blocks_for(user)
    sign_in user
    get "/api/v1/portal/team_settings", params: { client_account_id: team.id }
    response.parsed_body.dig("team_settings", "blocks")
  end

  it "does not show a team's settings to someone outside it" do
    outsider_team = ClientAccount.create!(organization:, name: "Outside", kind: :team)
    outsider = User.create!(organization:, name: "Outsider", email: "readable-outsider@example.test",
                            password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: outsider_team, user: outsider, role: :admin, status: :active)
    sign_in outsider

    get "/api/v1/portal/team_settings", params: { client_account_id: team.id }

    expect(response).to have_http_status(:not_found)
  end

  it "leaves out each block the team keeps from this person" do
    expect(blocks_for(member).keys).to eq([ "pricing" ])
    expect(blocks_for(admin).keys).to contain_exactly("billing", "pricing", "marketing_templates")
    expect(blocks_for(admin).dig("marketing_templates", "materials").sole).to include("title" => "Open house flyer")
    expect(blocks_for(member).dig("pricing", "products").sole.dig("variants", 0, "price_cents")).to eq(30_000)
  end
end
