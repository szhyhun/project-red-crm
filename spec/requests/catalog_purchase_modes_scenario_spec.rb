require "rails_helper"

RSpec.describe "Catalog purchase modes API scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Purchase modes agency", slug: "purchase-modes-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Purchase modes manager", email: "purchase-modes-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Purchase modes client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "73 Purchase Modes Street") }

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.where(is_default: true).update_all(enabled: false)
    sign_in manager
  end

  def create_product(attributes)
    post "/api/v1/products", params: { product: attributes }
    expect(response).to have_http_status(:created)

    response.parsed_body.fetch("product")
  end

  def create_order(variant_id)
    post "/api/v1/orders", params: {
      order: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: variant_id, quantity: 1 } ]
      }
    }
    expect(response).to have_http_status(:created)

    Order.find(response.parsed_body.dig("order", "id"))
  end

  def approve_order(order)
    post "/api/v1/orders/#{order.id}/approve"
    expect(response).to have_http_status(:ok)
    order.reload
  end

  it "sells one service both independently and inside a package without double billing" do
    service = create_product(
      slug: "purchase-modes-photography",
      title: "Standard Property Photography",
      description: "Interior and exterior photos.",
      kind: "service",
      deliverable_type: "photography",
      sla_days: 2,
      product_variants_attributes: [
        { title: "0–1,000 sqft", price_cents: 29_900, sqft_min: 0, sqft_max: 1_000 }
      ]
    )
    package = create_product(
      slug: "purchase-modes-package",
      title: "Photo package",
      kind: "package",
      deliverable_type: "other",
      product_variants_attributes: [
        { title: "0–1,000 sqft", price_cents: 59_900, sqft_min: 0, sqft_max: 1_000 }
      ]
    )

    post "/api/v1/products/#{package.fetch("id")}/components", params: {
      product_component: { service_product_id: service.fetch("id"), quantity: 1, position: 0 }
    }
    expect(response).to have_http_status(:created)

    standalone_order = create_order(service.fetch("variants").sole.fetch("id"))
    package_order = create_order(package.fetch("variants").sole.fetch("id"))
    approve_order(standalone_order)
    approve_order(package_order)

    expect(standalone_order.order_items.count).to eq(1)
    expect(standalone_order.total_cents).to eq(29_900)
    expect(standalone_order.order_deliverables.sole).to have_attributes(
      service_product_id: service.fetch("id"), product_component_id: nil,
      scope_sqft_min: 0, scope_sqft_max: 1_000, scope_label: "0–1,000 sqft"
    )

    expect(package_order.order_items.count).to eq(1)
    expect(package_order.total_cents).to eq(59_900)
    expect(package_order.order_deliverables.count).to eq(1)
    expect(package_order.order_deliverables.sole).to have_attributes(
      service_product_id: service.fetch("id"), product_component_id: be_present,
      scope_sqft_min: 0, scope_sqft_max: 1_000, scope_label: "0–1,000 sqft"
    )
  end

  it "keeps the sold price and scope when the catalog tier changes before approval" do
    service = create_product(
      slug: "purchase-modes-history",
      title: "Historical photography",
      kind: "service",
      deliverable_type: "photography",
      product_variants_attributes: [
        { title: "0–1,000 sqft", price_cents: 25_000, sqft_min: 0, sqft_max: 1_000 }
      ]
    )
    variant_id = service.fetch("variants").sole.fetch("id")
    order = create_order(variant_id)
    product = Product.find(service.fetch("id"))
    variant = ProductVariant.find(variant_id)

    patch "/api/v1/products/#{product.id}", params: {
      product: {
        product_variants_attributes: [
          { id: variant.id, title: "New 1,001–2,000 sqft", price_cents: 35_000, sqft_min: 1_001, sqft_max: 2_000 }
        ]
      }
    }
    expect(response).to have_http_status(:ok)

    approve_order(order)

    expect(order.order_items.sole).to have_attributes(unit_price_cents: 25_000, total_cents: 25_000)
    expect(order.order_deliverables.sole).to have_attributes(scope_sqft_min: 0, scope_sqft_max: 1_000,
                                                              scope_label: "0–1,000 sqft")
  end

  it "charges the customer-specific variant price through the order API" do
    service = create_product(
      slug: "purchase-modes-preferred-rate",
      title: "Preferred-rate photography",
      kind: "service",
      deliverable_type: "photography",
      product_variants_attributes: [
        { title: "0–1,000 sqft", price_cents: 30_000, sqft_min: 0, sqft_max: 1_000 }
      ]
    )
    variant = ProductVariant.find(service.fetch("variants").sole.fetch("id"))
    plan = organization.pricing_plans.create!(name: "Purchase modes client rate", client_account:)
    plan.pricing_plan_prices.create!(product_variant: variant, price_cents: 24_000)

    order = create_order(variant.id)

    expect(order.order_items.sole).to have_attributes(unit_price_cents: 24_000, total_cents: 24_000)
    expect(order.order_items.sole.snapshot).to include("price_cents" => 24_000)
    expect(order.total_cents).to eq(24_000)
  end
end
