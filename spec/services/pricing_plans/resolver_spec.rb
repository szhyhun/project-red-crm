require "rails_helper"

RSpec.describe PricingPlans::Resolver do
  let(:organization) { Organization.create!(name: "Pricing Agency", slug: "pricing-agency") }
  let(:team) { ClientAccount.create!(organization:, name: "Oak Bay Realty", kind: :team) }
  let(:person) do
    User.create!(organization:, name: "Avery Agent", email: "avery-pricing@example.test",
                 password: "long-enough-password", role: :client_member)
  end
  let(:product) { Product.create!(organization:, slug: "premium-photo", title: "Premium Photo", kind: :service) }
  let(:variant) { product.product_variants.create!(title: "Standard", price_cents: 50_000) }

  def resolve(user: nil)
    described_class.new(client_account: team, product_variant: variant, user:).price_cents
  end

  it "charges the list price when neither the team nor the person has a plan" do
    expect(resolve(user: person)).to eq(50_000)
  end

  it "charges the team's plan, and the list price for anything the plan leaves out" do
    plan = organization.pricing_plans.create!(name: "Team", client_account: team)
    plan.pricing_plan_prices.create!(product_variant: variant, price_cents: 42_000)
    expect(resolve).to eq(42_000)

    plan.pricing_plan_prices.destroy_all
    expect(resolve).to eq(50_000)
  end

  it "lets a price promised to the person beat the team's plan" do
    organization.pricing_plans.create!(name: "Team", client_account: team)
                .pricing_plan_prices.create!(product_variant: variant, price_cents: 42_000)
    organization.pricing_plans.create!(name: "Avery", user: person)
                .pricing_plan_prices.create!(product_variant: variant, price_cents: 39_000)

    expect(resolve(user: person)).to eq(39_000)
    expect(resolve).to eq(42_000)
  end

  it "ignores a plan that has been switched off" do
    organization.pricing_plans.create!(name: "Old", client_account: team, active: false)
                .pricing_plan_prices.create!(product_variant: variant, price_cents: 10_000)

    expect(resolve).to eq(50_000)
  end
end
