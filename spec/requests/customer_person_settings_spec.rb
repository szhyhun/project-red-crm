require "rails_helper"

RSpec.describe "Customer person settings", type: :request do
  let!(:organization) { Organization.create!(name: "Person agency", slug: "person-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Person manager", email: "person-manager@example.test",
                 password: "long-enough-password", role: :organization_admin)
  end
  let!(:account) { ClientAccount.create!(organization:, name: "Person Team", kind: :team) }
  let!(:client_user) do
    User.create!(organization:, name: "Ordering customer", email: "ordering-customer@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: account, user:, role: :admin, status: :active, is_default: true)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account: account, address_line_1: "Person Street") }
  let!(:product) do
    Product.create!(organization:, slug: "person-photography", title: "Property photography", kind: :service,
                    deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { product.product_variants.create!(title: "Standard", price_cents: 30_000) }

  def place_order(as:)
    sign_in as
    post "/api/v1/orders", params: {
      order: {
        client_account_id: account.id, listing_id: listing.id, payment_mode: "pay_later",
        items: [ { product_variant_id: variant.id, quantity: 1 } ]
      }
    }
  end

  it "refuses an order from a customer who is blocked from ordering" do
    client_user.update!(blocked_from_ordering: true)

    expect { place_order(as: client_user) }.not_to change(Order, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "base")).to include("This customer cannot place orders")
  end

  it "still lets staff place an order for that customer" do
    client_user.update!(blocked_from_ordering: true)

    expect { place_order(as: manager) }.to change(Order, :count).by(1)

    expect(response).to have_http_status(:created)
  end

  it "charges the team's plan when the person has no override" do
    team_plan = organization.pricing_plans.create!(name: "Team rate", client_account: account)
    team_plan.pricing_plan_prices.create!(product_variant: variant, price_cents: 25_000)

    place_order(as: client_user)

    expect(response).to have_http_status(:created)
    expect(Order.order(:id).last.order_items.sole.unit_price_cents).to eq(25_000)
  end

  it "lets a price promised to one person beat their team's plan" do
    team_plan = organization.pricing_plans.create!(name: "Team rate", client_account: account)
    team_plan.pricing_plan_prices.create!(product_variant: variant, price_cents: 25_000)
    personal = organization.pricing_plans.create!(name: "Promised rate", user: client_user)
    personal.pricing_plan_prices.create!(product_variant: variant, price_cents: 19_900)

    place_order(as: client_user)

    expect(response).to have_http_status(:created)
    expect(Order.order(:id).last.order_items.sole.unit_price_cents).to eq(19_900)
  end

  it "refuses a pricing plan that belongs to two owners at once" do
    plan = organization.pricing_plans.build(name: "Confused", client_account: account, user: client_user)

    expect(plan).not_to be_valid
    expect(plan.errors.full_messages).to include("must belong to exactly one client account, customer team, or person")
  end
end
