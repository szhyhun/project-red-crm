require "rails_helper"

RSpec.describe "Order deliverable API", type: :request do
  let!(:organization) { Organization.create!(name: "Deliverable Agency", slug: "deliverable-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Deliverable Agency", slug: "other-deliverable-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Deliverable Manager", email: "deliverable-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Deliverable Client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Deliverable Client User", email: "deliverable-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "3 Deliverable Street") }
  let!(:service) do
    Product.create!(organization:, slug: "deliverable-photo", title: "Property photography", kind: :service,
                    deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 30_000) }
  let!(:order) do
    Orders::Create.call(
      organization:,
      attributes: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: variant.id, quantity: 1 } ]
      }
    ).fetch(:order)
  end
  let!(:deliverable) do
    order.update!(status: :approved, approved_at: Time.current)
    Orders::DeliverableMaterializer.new(order:).call.sole
  end

  before { sign_in manager }

  it "lists deliverables under an order and includes the customer-safe count" do
    asset = deliverable.media_assets.create!(organization:, listing:, kind: :final, status: :ready,
                                              storage_key: "deliverable-agency/front.jpg", filename: "front.jpg",
                                              content_type: "image/jpeg", customer_visible: true)

    get "/api/v1/orders/#{order.id}/deliverables"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("order_deliverables").sole).to include(
      "id" => deliverable.id, "title" => "Property photography", "asset_count" => 1
    )
    expect(asset).to be_persisted
  end

  it "updates the delivery state and timestamps it when marked delivered" do
    expect {
      patch "/api/v1/order_deliverables/#{deliverable.id}", params: {
        order_deliverable: { status: "delivered", target_on: "2026-09-12" }
      }
    }.to change { deliverable.reload.delivered_at }.from(nil)

    expect(response).to have_http_status(:ok)
    expect(deliverable.reload).to have_attributes(status: "delivered", target_on: Date.new(2026, 9, 12))
    expect(response.parsed_body.dig("order_deliverable", "status")).to eq("delivered")
    expect(deliverable.activity_events.where(event_type: "order_deliverable.updated")).to exist
  end

  it "clears delivered_at when work moves back into production" do
    deliverable.update!(status: :delivered, delivered_at: 1.day.ago)

    patch "/api/v1/order_deliverables/#{deliverable.id}", params: {
      order_deliverable: { status: "in_progress" }
    }

    expect(response).to have_http_status(:ok)
    expect(deliverable.reload).to have_attributes(status: "in_progress", delivered_at: nil)
  end

  it "allows the customer to view its own deliverables but not modify them" do
    sign_out manager
    sign_in client_user

    get "/api/v1/order_deliverables/#{deliverable.id}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("order_deliverable", "id")).to eq(deliverable.id)

    patch "/api/v1/order_deliverables/#{deliverable.id}", params: {
      order_deliverable: { status: "delivered" }
    }
    expect(response).to have_http_status(:forbidden)
    expect(deliverable.reload.status).to eq("not_started")
  end

  it "does not expose another organization's deliverable" do
    other_client = ClientAccount.create!(organization: other_organization, name: "Other Client", kind: :agent)
    other_listing = Listing.create!(organization: other_organization, client_account: other_client,
                                    address_line_1: "Hidden Deliverable Street")
    other_product = other_organization.products.create!(slug: "other-deliverable-service", title: "Other service",
                                                         kind: :service, deliverable_type: "video")
    other_variant = other_product.product_variants.create!(title: "Standard", price_cents: 10_000)
    other_order = Orders::Create.call(
      organization: other_organization,
      attributes: {
        client_account_id: other_client.id,
        listing_id: other_listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: other_variant.id, quantity: 1 } ]
      }
    ).fetch(:order)
    other_order.update!(status: :approved, approved_at: Time.current)
    other_deliverable = Orders::DeliverableMaterializer.new(order: other_order).call.sole

    get "/api/v1/order_deliverables/#{other_deliverable.id}"

    expect(response).to have_http_status(:not_found)
  end

  it "includes deliverables in the staff listing payload" do
    get "/api/v1/listings/#{listing.id}"

    expect(response).to have_http_status(:ok)
    serialized = response.parsed_body.fetch("listing").fetch("order_deliverables").sole
    expect(serialized).to include("id" => deliverable.id, "service_product_id" => service.id, "status" => "not_started")
  end
end
