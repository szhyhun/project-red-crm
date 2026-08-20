require "rails_helper"

RSpec.describe PricingPlans::Resolver do
  let(:organization) { Organization.create!(name: "Pricing Agency", slug: "pricing-agency") }
  let(:client) { ClientAccount.create!(organization:, name: "Avery Agent") }
  let(:product) { Product.create!(organization:, slug: "premium-photo", title: "Premium Photo", kind: :service) }
  let(:variant) { product.product_variants.create!(title: "Standard", price_cents: 50_000) }

  def resolve
    described_class.new(client_account: client, product_variant: variant).price_cents
  end

  it "uses a client plan over a team plan" do
    team = organization.customer_teams.create!(name: "Oak Bay Realty")
    team.customer_team_memberships.create!(client_account: client)
    team_plan = organization.pricing_plans.create!(name: "Team", customer_team: team)
    team_plan.pricing_plan_prices.create!(product_variant: variant, price_cents: 42_000)
    client_plan = organization.pricing_plans.create!(name: "Client", client_account: client)
    client_plan.pricing_plan_prices.create!(product_variant: variant, price_cents: 39_000)

    expect(resolve).to eq(39_000)
  end

  it "uses team priority and falls back to the catalog price" do
    first_team = organization.customer_teams.create!(name: "First Team")
    second_team = organization.customer_teams.create!(name: "Second Team")
    [ first_team, second_team ].each { |team| team.customer_team_memberships.create!(client_account: client) }
    first_plan = organization.pricing_plans.create!(name: "First", customer_team: first_team, priority: 10)
    first_plan.pricing_plan_prices.create!(product_variant: variant, price_cents: 44_000)
    second_plan = organization.pricing_plans.create!(name: "Second", customer_team: second_team, priority: 1)
    second_plan.pricing_plan_prices.create!(product_variant: variant, price_cents: 43_000)

    expect(resolve).to eq(43_000)

    second_plan.pricing_plan_prices.destroy_all
    first_plan.pricing_plan_prices.destroy_all
    expect(resolve).to eq(50_000)
  end
end
