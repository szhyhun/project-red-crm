require "rails_helper"

RSpec.describe Orders::Create, type: :interactor do
  it "uses the catalog variant price instead of a client-provided price" do
    organization = Organization.create!(name: "ProjectRed", slug: "projectred")
    client = ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent)
    product = Product.create!(organization:, slug: "premium-photos", title: "Premium Photos", kind: :service)
    variant = product.product_variants.create!(title: "Up to 2,000 sqft", price_cents: 45_000)

    result = described_class.call(
      organization:,
      attributes: {
        client_account_id: client.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: variant.id, quantity: 2, unit_price_cents: 1 } ]
      }
    )
    expect(result).to be_success
    order = result.fetch(:order)

    expect(order).to have_attributes(subtotal_cents: 90_000, total_cents: 90_000)
    expect(order.order_items.first).to have_attributes(unit_price_cents: 45_000, total_cents: 90_000)
    expect(order.order_items.first.snapshot).to include(
      "sqft_min" => nil,
      "sqft_max" => nil,
      "quantity_label" => nil
    )
  end

  it "uses an active client pricing-plan override and snapshots the effective price" do
    organization = Organization.create!(name: "Plan pricing project", slug: "plan-pricing-project")
    client = ClientAccount.create!(organization:, name: "Plan pricing client", kind: :agent)
    product = Product.create!(organization:, slug: "plan-priced-photos", title: "Plan-priced Photos", kind: :service)
    variant = product.product_variants.create!(title: "Standard", price_cents: 45_000)
    plan = organization.pricing_plans.create!(name: "Preferred client rates", client_account: client)
    plan.pricing_plan_prices.create!(product_variant: variant, price_cents: 39_000)

    result = described_class.call(
      organization:,
      attributes: {
        client_account_id: client.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: variant.id, quantity: 2, unit_price_cents: 1 } ]
      }
    )
    expect(result).to be_success
    order = result.fetch(:order)

    item = order.order_items.sole
    expect(item).to have_attributes(unit_price_cents: 39_000, total_cents: 78_000)
    expect(item.snapshot).to include("price_cents" => 39_000)
    expect(order.total_cents).to eq(78_000)
  end
end
