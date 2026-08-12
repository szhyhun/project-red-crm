require "rails_helper"

RSpec.describe "Order item management", type: :request do
  let(:organization) { Organization.create!(name: "Order Agency", slug: "order-agency") }
  let(:manager) { User.create!(organization:, name: "Manager", email: "order-manager@example.test", password: "long-enough-password", role: :manager) }
  let(:client) { ClientAccount.create!(organization:, name: "Agent", email: "agent-order@example.test", kind: :agent) }
  let(:listing) { Listing.create!(organization:, client_account: client, address_line_1: "111 Oak Bay Avenue") }
  let(:order) { Order.create!(organization:, client_account: client, listing:, payment_mode: :pay_later) }
  let(:product) { Product.create!(organization:, slug: "premium-photo", title: "Premium Photo", kind: :service, active: true) }
  let(:variant) { product.product_variants.create!(title: "Up to 2,000 sqft", price_cents: 25000, active: true) }

  before { sign_in manager }

  it "creates and soft cancels a custom item while recalculating totals" do
    post "/api/v1/orders/#{order.id}/items", params: {
      order_item: { title: "Custom rush edit", quantity: 2, unit_price_cents: 2500 }
    }
    expect(response).to have_http_status(:created)
    item = order.order_items.last
    expect(order.reload.total_cents).to eq(5000)

    sign_in manager
    delete "/api/v1/orders/#{order.id}/items/#{item.id}"
    expect(response).to have_http_status(:ok)
    expect(item.reload.cancelled_at).to be_present
    expect(order.reload.total_cents).to eq(0)
  end

  it "adds an active catalog variant to an existing order" do
    post "/api/v1/orders/#{order.id}/items", params: {
      order_item: { product_variant_id: variant.id, quantity: 2 }
    }

    expect(response).to have_http_status(:created)
    item = order.order_items.last
    expect(item).to have_attributes(
      product: product,
      product_variant: variant,
      title: "Premium Photo - Up to 2,000 sqft",
      unit_price_cents: 25000,
      total_cents: 50000
    )
    expect(item.snapshot).to include("product_title" => "Premium Photo", "variant_title" => "Up to 2,000 sqft")
    expect(order.reload.total_cents).to eq(50000)
  end
end
