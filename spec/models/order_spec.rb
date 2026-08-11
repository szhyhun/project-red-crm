require "rails_helper"

RSpec.describe Order, type: :model do
  it "calculates totals from persisted order items without changing selected prices" do
    organization = Organization.create!(name: "ProjectRed", slug: "projectred")
    client = ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent)
    order = Order.create!(organization:, client_account: client, discount_cents: 500, tax_cents: 1_245)
    order.order_items.create!(title: "Premium Photos", quantity: 1, unit_price_cents: 45_000, total_cents: 45_000)
    order.order_items.create!(title: "Aerial Photos", quantity: 1, unit_price_cents: 12_500, total_cents: 12_500)

    order.recalculate_totals!

    expect(order).to have_attributes(subtotal_cents: 57_500, total_cents: 58_245)
  end
end
