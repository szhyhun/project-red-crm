require "rails_helper"

RSpec.describe "Catalog snapshot API scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Catalog snapshot agency", slug: "catalog-snapshot-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Catalog snapshot manager", email: "catalog-snapshot-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Catalog snapshot client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "12 Catalog Snapshot Street") }

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.update_all(enabled: false)
    sign_in manager
  end

  def create_product(attributes)
    post "/api/v1/products", params: { product: attributes }
    expect(response).to have_http_status(:created)

    response.parsed_body.fetch("product")
  end

  it "keeps the purchased package services stable when catalog data changes before approval" do
    service = create_product(
      slug: "catalog-snapshot-service",
      title: "Standard Property Photography",
      description: "Interior and exterior photos for the property.",
      kind: "service",
      deliverable_type: "photography",
      sla_days: 2,
      product_variants_attributes: [
        { title: "0–1,000 sqft", price_cents: 29_900, sqft_min: 0, sqft_max: 1_000 }
      ]
    )
    package = create_product(
      slug: "catalog-snapshot-package",
      title: "Complete media package",
      description: "Photography and delivery services.",
      kind: "package",
      deliverable_type: "other",
      product_variants_attributes: [
        { title: "0–1,000 sqft", price_cents: 59_900, sqft_min: 0, sqft_max: 1_000 }
      ]
    )

    post "/api/v1/products/#{package.fetch("id")}/components", params: {
      product_component: { service_product_id: service.fetch("id"), quantity: 2, position: 0 }
    }
    expect(response).to have_http_status(:created)
    component_id = response.parsed_body.dig("component", "id")

    post "/api/v1/orders", params: {
      order: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: package.fetch("variants").sole.fetch("id"), quantity: 1 } ]
      }
    }
    expect(response).to have_http_status(:created)
    order_id = response.parsed_body.dig("order", "id")

    patch "/api/v1/products/#{service.fetch("id")}", params: {
      product: {
        title: "Renamed Photography Service",
        description: "A new service description added after checkout.",
        deliverable_type: "video",
        sla_days: 10
      }
    }
    expect(response).to have_http_status(:ok)

    patch "/api/v1/products/#{package.fetch("id")}/components/#{component_id}", params: {
      product_component: { quantity: 4 }
    }
    expect(response).to have_http_status(:ok)

    post "/api/v1/orders/#{order_id}/approve"

    expect(response).to have_http_status(:ok)
    order = Order.find(order_id)
    deliverable = order.order_deliverables.sole

    expect(order.order_items).to contain_exactly(have_attributes(total_cents: 59_900))
    expect(deliverable).to have_attributes(
      product_component_id: component_id,
      service_product_id: service.fetch("id"),
      title: "Standard Property Photography",
      description: "Interior and exterior photos for the property.",
      deliverable_type: "photography",
      sla_days: 2
    )
    expect(deliverable.metadata).to include("quantity" => 1, "component_quantity" => 2)
    expect(response.parsed_body.dig("order", "deliverables").sole).to include(
      "title" => "Standard Property Photography",
      "deliverable_type" => "photography",
      "sla_days" => 2
    )
  end
end
