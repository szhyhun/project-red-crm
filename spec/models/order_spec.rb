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

  it "calculates a percentage discount and separate service fee" do
    organization = Organization.create!(name: "ProjectRed", slug: "projectred-percentage")
    client = ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent)
    order = Order.create!(organization:, client_account: client, discount_type: :percentage,
                          discount_rate_basis_points: 1_000, tax_cents: 2_000, fee_cents: 500)
    order.order_items.create!(title: "Video", quantity: 1, unit_price_cents: 50_000, total_cents: 50_000)

    order.recalculate_totals!

    expect(order).to have_attributes(subtotal_cents: 50_000, discount_cents: 5_000, total_cents: 47_500)
  end

  it "rejects a listing that belongs to a different customer account" do
    organization = Organization.create!(name: "ProjectRed", slug: "projectred-order-account-boundary")
    selected_account = ClientAccount.create!(organization:, name: "Selected account", kind: :agent)
    other_account = ClientAccount.create!(organization:, name: "Other account", kind: :agent)
    listing = Listing.create!(organization:, client_account: other_account, address_line_1: "Foreign customer listing")

    order = Order.new(organization:, client_account: selected_account, listing:)

    expect(order).not_to be_valid
    expect(order.errors.full_messages).to include("Listing must belong to the selected customer account")
  end
end
