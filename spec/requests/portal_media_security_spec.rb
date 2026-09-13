require "rails_helper"

RSpec.describe "Portal media authorization", type: :request do
  let!(:organization) { Organization.create!(name: "Portal Security Agency", slug: "portal-security-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Portal Security", slug: "other-portal-security") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Portal security client", kind: :agent) }
  let!(:other_client_account) { ClientAccount.create!(organization:, name: "Other portal client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Portal security user", email: "portal-security@example.test",
                 password: "long-enough-password", role: :client_member).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :member)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "14 Portal Street") }
  let!(:other_listing) { Listing.create!(organization:, client_account: other_client_account, address_line_1: "15 Private Street") }
  let!(:service) do
    organization.products.create!(slug: "portal-security-service", title: "Portal security photos", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:order) do
    Orders::Create.call(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).fetch(:order).tap do |record|
      record.update!(status: :approved, approved_at: Time.current)
    end
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }

  before { sign_in client_user }

  it "shows only active deliverables and customer-visible ready final assets" do
    visible = deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                                kind: :final, status: :ready,
                                                source_url: "https://cdn.example.test/portal-visible.jpg",
                                                filename: "portal-visible.jpg", content_type: "image/jpeg",
                                                customer_visible: true)
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                     kind: :final, status: :processing,
                                     source_url: "https://cdn.example.test/portal-processing.jpg",
                                     filename: "portal-processing.jpg", content_type: "image/jpeg",
                                     customer_visible: true)
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                     kind: :raw, status: :ready,
                                     source_url: "https://cdn.example.test/portal-raw.jpg",
                                     filename: "portal-raw.jpg", content_type: "image/jpeg",
                                     customer_visible: true)
    cancelled = order.order_deliverables.create!(organization:, listing:, order_item: order.order_items.sole,
                                                  service_product: service, title: "Cancelled service",
                                                  deliverable_type: "photography", sla_days: 0,
                                                  cancelled_at: Time.current,
                                                  materialization_key: "portal-cancelled-#{SecureRandom.uuid}")

    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload.fetch("deliverables").pluck("id")).to eq([ deliverable.id ])
    expect(payload.dig("deliverables", 0, "assets").pluck("id")).to eq([ visible.id ])
    expect(payload.fetch("deliverables").pluck("id")).not_to include(cancelled.id)
    expect(payload.dig("deliverables", 0, "assets", 0)).not_to have_key("source_url")
  end

  it "does not expose a listing or deliverable owned by another customer account" do
    foreign_service = organization.products.create!(slug: "foreign-portal-service", title: "Foreign portal service",
                                                     kind: :service, deliverable_type: "video")
    foreign_variant = foreign_service.product_variants.create!(title: "Standard", price_cents: 10_000)
    foreign_order = Orders::Create.call(organization:, attributes: {
      client_account_id: other_client_account.id, listing_id: other_listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: foreign_variant.id, quantity: 1 } ]
    }).fetch(:order)
    foreign_order.update!(status: :approved, approved_at: Time.current)
    foreign_deliverable = Orders::DeliverableMaterializer.new(order: foreign_order).call.sole

    get "/api/v1/portal/listings/#{other_listing.id}/media"
    expect(response).to have_http_status(:not_found)

    get "/api/v1/order_deliverables/#{foreign_deliverable.id}"
    expect(response).to have_http_status(:not_found)
  end

  it "does not let a customer request changes before delivery" do
    expect {
      post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
        change_request: { body: "Please revise this" }
      }
    }.not_to change(Message, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to eq("change_requests_only_for_delivered_work")
    expect(deliverable.reload).not_to be_delivered
  end

  it "does not let a customer preview a hidden or not-ready asset" do
    hidden = deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                               kind: :final, status: :ready,
                                               source_url: "https://cdn.example.test/portal-hidden.jpg",
                                               filename: "portal-hidden.jpg", content_type: "image/jpeg",
                                               customer_visible: false)
    pending = deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                                kind: :final, status: :pending,
                                                source_url: "https://cdn.example.test/portal-pending.jpg",
                                                filename: "portal-pending.jpg", content_type: "image/jpeg",
                                                customer_visible: true)

    get "/api/v1/media_assets/#{hidden.id}/preview"
    expect(response).to have_http_status(:not_found)

    get "/api/v1/media_assets/#{pending.id}/preview"
    expect(response).to have_http_status(:not_found)
  end

  it "allows a directly owned listing but not a listing shared through another account" do
    get "/api/v1/portal/listings/#{listing.id}"
    expect(response).to have_http_status(:ok)

    get "/api/v1/portal/listings/#{other_listing.id}"
    expect(response).to have_http_status(:not_found)
  end

  it "does not allow a customer to use a deliverable endpoint as a write path" do
    patch "/api/v1/order_deliverables/#{deliverable.id}", params: {
      order_deliverable: { status: "delivered" }
    }

    expect(response).to have_http_status(:forbidden)
    expect(deliverable.reload.status).to eq("not_started")
  end

  it "does not let a customer fetch a cancelled deliverable directly" do
    deliverable.update!(cancelled_at: Time.current)

    get "/api/v1/order_deliverables/#{deliverable.id}"

    expect(response).to have_http_status(:not_found)
  end

  it "does not expose another organization's listing through a same-email portal account" do
    foreign_client = ClientAccount.create!(organization: other_organization, name: "Foreign account", kind: :agent)
    foreign_listing = Listing.create!(organization: other_organization, client_account: foreign_client,
                                      address_line_1: "Foreign portal address")

    get "/api/v1/portal/listings/#{foreign_listing.id}"

    expect(response).to have_http_status(:not_found)
  end
end
