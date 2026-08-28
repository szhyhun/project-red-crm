require "rails_helper"

RSpec.describe Orders::Creator do
  it "uses the catalog variant price instead of a client-provided price" do
    organization = Organization.create!(name: "ProjectRed", slug: "projectred")
    client = ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent)
    product = Product.create!(organization:, slug: "premium-photos", title: "Premium Photos", kind: :service)
    variant = product.product_variants.create!(title: "Up to 2,000 sqft", price_cents: 45_000)

    order = described_class.new(
      organization:,
      attributes: {
        client_account_id: client.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: variant.id, quantity: 2, unit_price_cents: 1 } ]
      }
    ).create!

    expect(order).to have_attributes(subtotal_cents: 90_000, total_cents: 90_000)
    expect(order.order_items.first).to have_attributes(unit_price_cents: 45_000, total_cents: 90_000)
  end
end
