require "rails_helper"

RSpec.describe "Person and team price lists", type: :request do
  let!(:organization) { Organization.create!(name: "Price list agency", slug: "price-list-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Price manager", email: "price-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:specialist) do
    User.create!(organization:, name: "Price specialist", email: "price-specialist@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:person) do
    User.create!(organization:, name: "Priced person", email: "priced-person@example.test",
                 password: "long-enough-password", role: :client_member)
  end
  let!(:product) { Product.create!(organization:, slug: "price-list-photos", title: "Photos", kind: :service) }
  let!(:standard) { product.product_variants.create!(title: "Standard", price_cents: 30_000) }
  let!(:large) { product.product_variants.create!(title: "Large", price_cents: 45_000) }

  let(:body) do
    { pricing_plan: { name: "Priced person prices", active: true, user_id: person.id,
                      pricing_plan_prices_attributes: [ { product_variant_id: standard.id, price_cents: 25_000 },
                                                        { product_variant_id: large.id, price_cents: 40_000 } ] } }
  end

  it "does not let production staff promise a person a price" do
    sign_in specialist

    post "/api/v1/pricing_plans", params: body, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(PricingPlan.count).to eq(0)
  end

  it "saves a person's prices, then drops one back to the list price" do
    sign_in manager

    post "/api/v1/pricing_plans", params: body, as: :json
    expect(response).to have_http_status(:created)
    plan = PricingPlan.find(response.parsed_body.dig("pricing_plan", "id"))
    large_price = plan.pricing_plan_prices.find_by!(product_variant: large)

    patch "/api/v1/pricing_plans/#{plan.id}", params: {
      pricing_plan: { pricing_plan_prices_attributes: [ { id: large_price.id, _destroy: true } ] }
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(plan.reload.pricing_plan_prices.pluck(:product_variant_id, :price_cents)).to eq([ [ standard.id, 25_000 ] ])
    expect(PricingPlans::Resolver.new(client_account: ClientAccount.create!(organization:, name: "Any team"),
                                      product_variant: large, user: person).price_cents).to eq(45_000)
  end
end
