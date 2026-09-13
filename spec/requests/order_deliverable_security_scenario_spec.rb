require "rails_helper"

RSpec.describe "Order deliverable security API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Deliverable security agency", slug: "deliverable-security-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Deliverable security manager", email: "deliverable-security-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_user) do
    User.create!(organization:, name: "Deliverable security customer", email: "deliverable-security-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Deliverable security client", kind: :agent) }
  let!(:other_account) { ClientAccount.create!(organization:, name: "Other deliverable client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "22 Deliverable Security Street") }
  let!(:other_listing) { Listing.create!(organization:, client_account: other_account, address_line_1: "23 Hidden Security Street") }
  let!(:service) do
    organization.products.create!(slug: "deliverable-security-service", title: "Security photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:order) { create_order(client_account:, listing:) }
  let!(:deliverable) { materialize(order) }
  let!(:other_order) { create_order(client_account: other_account, listing: other_listing) }
  let!(:other_deliverable) { materialize(other_order) }

  before { sign_in manager }

  it "returns only customer-safe fields when a customer reads its own deliverable" do
    sign_out manager
    sign_in client_user

    get "/api/v1/order_deliverables/#{deliverable.id}"

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch("order_deliverable")
    expect(payload).to include("id" => deliverable.id, "status" => "not_started", "assets" => [])
    expect(payload).not_to include(
      "organization_id", "listing_id", "order_id", "order_item_id", "product_component_id",
      "service_product_id", "materialization_key", "metadata", "workflow_tasks"
    )
  end

  it "does not resolve another customer account through order or deliverable routes" do
    sign_out manager
    sign_in client_user

    get "/api/v1/orders/#{other_order.id}/deliverables"
    expect(response).to have_http_status(:not_found)

    get "/api/v1/order_deliverables/#{other_deliverable.id}"
    expect(response).to have_http_status(:not_found)
  end

  it "ignores lineage fields that a staff caller must not be able to rewrite" do
    original = deliverable.attributes.slice("order_id", "order_item_id", "service_product_id", "materialization_key")

    patch "/api/v1/order_deliverables/#{deliverable.id}", params: {
      order_deliverable: {
        status: "in_progress",
        order_id: other_order.id,
        order_item_id: other_order.order_items.sole.id,
        service_product_id: other_deliverable.service_product_id,
        materialization_key: "forged-materialization-key",
        organization_id: organization.id + 10_000
      }
    }

    expect(response).to have_http_status(:ok)
    expect(deliverable.reload).to have_attributes(status: "in_progress", **original.symbolize_keys)
  end

  it "rejects an unknown delivery status without changing the record or activity" do
    deliverable.update!(status: :in_progress)
    original_target_on = deliverable.target_on
    activity_count = ActivityEvent.where(subject: deliverable, event_type: "order_deliverable.updated").count

    patch "/api/v1/order_deliverables/#{deliverable.id}", params: {
      order_deliverable: { status: "shipped", target_on: "2026-09-30" }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "status")).to be_present
    expect(deliverable.reload).to have_attributes(status: "in_progress", target_on: original_target_on)
    expect(ActivityEvent.where(subject: deliverable, event_type: "order_deliverable.updated").count)
      .to eq(activity_count)
  end

  it "does not let a customer update delivery state or target dates" do
    sign_out manager
    sign_in client_user
    original_target_on = deliverable.target_on

    patch "/api/v1/order_deliverables/#{deliverable.id}", params: {
      order_deliverable: { status: "delivered", target_on: "2026-09-30" }
    }

    expect(response).to have_http_status(:forbidden)
    expect(deliverable.reload).to have_attributes(status: "not_started", target_on: original_target_on)
  end

  private

  def create_order(client_account:, listing:)
    Orders::Create.call(organization:, attributes: {
      client_account_id: client_account.id,
      listing_id: listing.id,
      payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).fetch(:order).tap { |record| record.update!(status: :approved, approved_at: Time.current) }
  end

  def materialize(order)
    Orders::DeliverableMaterializer.new(order:).call.sole
  end
end
