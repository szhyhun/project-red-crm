require "rails_helper"

require "tempfile"

RSpec.describe "Media delivery routes API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Delivery routes agency", slug: "delivery-routes-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Delivery routes manager", email: "delivery-routes-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Delivery routes client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Delivery routes client user", email: "delivery-routes-client@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "70 Delivery Routes Street") }
  let!(:service) do
    organization.products.create!(slug: "delivery-routes-service", title: "Property photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 25_000) }
  let!(:order) do
    Orders::Creator.new(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).create!.tap do |record|
      record.update!(status: :approved, approved_at: Time.zone.parse("2026-09-07 09:00:00"))
    end
  end
  let!(:deliverable) do
    Orders::DeliverableMaterializer.new(order:).call.sole.tap do |record|
      record.update!(status: :delivered, delivered_at: Time.zone.parse("2026-09-08 09:00:00"))
    end
  end

  before { sign_in manager }

  it "lets an authorized customer preview and download a private ready asset through API routes" do
    asset = deliverable.media_assets.create!(
      organization:, listing:, order:, order_item: order.order_items.sole,
      kind: :final, status: :ready, storage_key: "organizations/#{organization.id}/deliverables/#{deliverable.id}/front.jpg",
      filename: "front.jpg", content_type: "image/jpeg", byte_size: 12, customer_visible: true
    )
    tempfile = Tempfile.new([ "delivery-routes", ".jpg" ])
    tempfile.binmode
    tempfile.write("private image")
    tempfile.flush
    allow(DeliveryStorage).to receive(:s3?).and_return(false)
    allow(DeliveryStorage).to receive(:path_for).with(asset.storage_key).and_return(tempfile.path)

    sign_out manager
    sign_in client_user

    get "/api/v1/media_assets/#{asset.id}/preview"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/jpeg")
    expect(response.headers.fetch("Content-Disposition")).to include("inline")

    get "/api/v1/media_assets/#{asset.id}/download"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/octet-stream")
    expect(response.headers.fetch("Content-Disposition")).to include("attachment")
  ensure
    tempfile&.close!
  end

  it "redirects an authorized customer to an approved external delivery source" do
    asset = deliverable.media_assets.create!(
      organization:, listing:, order:, order_item: order.order_items.sole,
      kind: :final, status: :ready, source_url: "https://cdn.example.test/deliveries/front.jpg",
      filename: "front.jpg", content_type: "image/jpeg", byte_size: 12, customer_visible: true
    )

    sign_out manager
    sign_in client_user

    get "/api/v1/media_assets/#{asset.id}/preview"
    expect(response).to redirect_to("https://cdn.example.test/deliveries/front.jpg")

    get "/api/v1/media_assets/#{asset.id}/download"
    expect(response).to redirect_to("https://cdn.example.test/deliveries/front.jpg")
  end

  it "does not stream hidden or superseded assets to a customer" do
    hidden = deliverable.media_assets.create!(
      organization:, listing:, order:, order_item: order.order_items.sole,
      kind: :final, status: :ready, storage_key: "private/hidden.jpg", filename: "hidden.jpg",
      content_type: "image/jpeg", byte_size: 5, customer_visible: false
    )
    replacement = deliverable.media_assets.create!(
      organization:, listing:, order:, order_item: order.order_items.sole,
      kind: :final, status: :ready, storage_key: "private/replacement.jpg", filename: "replacement.jpg",
      content_type: "image/jpeg", byte_size: 5, customer_visible: true, version: 2
    )
    original = deliverable.media_assets.create!(
      organization:, listing:, order:, order_item: order.order_items.sole,
      kind: :final, status: :ready, storage_key: "private/original.jpg", filename: "original.jpg",
      content_type: "image/jpeg", byte_size: 5, customer_visible: true, version: 1, superseded_by: replacement
    )

    sign_out manager
    sign_in client_user

    get "/api/v1/media_assets/#{hidden.id}/download"
    expect(response).to have_http_status(:not_found)

    get "/api/v1/media_assets/#{original.id}/preview"
    expect(response).to have_http_status(:not_found)
  end

  it "does not expose a private media route before the customer signs in" do
    asset = deliverable.media_assets.create!(
      organization:, listing:, order:, order_item: order.order_items.sole,
      kind: :final, status: :ready, storage_key: "private/unauthenticated.jpg", filename: "unauthenticated.jpg",
      content_type: "image/jpeg", byte_size: 5, customer_visible: true
    )

    sign_out manager
    get "/api/v1/media_assets/#{asset.id}/preview"

    expect(response).to have_http_status(:unauthorized)
  end
end
