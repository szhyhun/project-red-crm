require "rails_helper"

RSpec.describe "Portal media asset type scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Portal media types agency", slug: "portal-media-types") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Portal media types client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Portal media customer", email: "portal-media-types@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "80 Portal Media Street") }
  let!(:products) do
    [
      [ "Portal photography", "portal-types-photography", "photography" ],
      [ "Portal video", "portal-types-video", "video" ],
      [ "Portal floor plan", "portal-types-floor-plan", "floor_plan" ],
      [ "Portal files", "portal-types-files", "files" ]
    ].map do |title, slug, deliverable_type|
      organization.products.create!(title:, slug:, kind: :service, deliverable_type:, sla_days: 2).tap do |product|
        product.product_variants.create!(title: "Standard", price_cents: 10_000)
      end
    end
  end
  let!(:order) do
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later, status: :approved,
                  approved_at: Time.current).tap do |record|
      products.each do |product|
        variant = product.product_variants.sole
        record.order_items.create!(product:, product_variant: variant, title: product.title, quantity: 1,
                                   unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
      end
    end
  end
  let!(:deliverables) do
    order.order_items.map.with_index do |item, index|
      order.order_deliverables.create!(organization:, listing:, order_item: item, service_product: item.product,
                                       title: item.product.title, deliverable_type: item.product.deliverable_type,
                                       sla_days: 2, status: :delivered, delivered_at: Time.current, position: index,
                                       materialization_key: "portal-types-#{index}-#{SecureRandom.uuid}")
    end
  end

  before { sign_in client_user }

  it "returns each supported deliverable type with authorized API-relative asset routes" do
    assets = deliverables.map.with_index do |deliverable, index|
      content_type, filename, category = case deliverable.deliverable_type
      when "photography" then [ "image/jpeg", "front.jpg", "images" ]
      when "video" then [ "tour.mp4", "video/mp4", "videos" ]
      when "floor_plan" then [ "plan.pdf", "application/pdf", "floor_plans" ]
      else [ "notes.pdf", "application/pdf", "files" ]
      end
      deliverable.media_assets.create!(organization:, listing:, order:, order_item: deliverable.order_item,
                                       kind: :final, status: :ready, category:, storage_key: "portal-types/#{index}/#{filename}",
                                       filename:, content_type:, byte_size: 5, customer_visible: true)
    end

    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload.fetch("summary")).to include("deliverable_count" => 4, "delivered_count" => 4)
    expect(payload.fetch("deliverables").pluck("deliverable_type")).to contain_exactly(
      "photography", "video", "floor_plan", "files"
    )

    assets.each do |asset|
      serialized = payload.fetch("deliverables").flat_map { |entry| entry.fetch("assets") }.find { |entry| entry["id"] == asset.id }
      expect(serialized).to include(
        "id" => asset.id,
        "filename" => asset.filename,
        "content_type" => asset.content_type,
        "preview_path" => "/api/v1/media_assets/#{asset.id}/preview",
        "download_path" => "/api/v1/media_assets/#{asset.id}/download"
      )
      expect(serialized.keys).not_to include("storage_key", "source_url", "customer_visible", "hidden")
    end
  end

  it "returns a useful empty state while filtering pending, raw, hidden, and superseded files" do
    deliverable = deliverables.first
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: deliverable.order_item,
                                     kind: :raw, status: :ready, storage_key: "portal-types/raw.jpg",
                                     filename: "raw.jpg", content_type: "image/jpeg", byte_size: 5, customer_visible: true)
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: deliverable.order_item,
                                     kind: :final, status: :pending, storage_key: "portal-types/pending.jpg",
                                     filename: "pending.jpg", content_type: "image/jpeg", byte_size: 5, customer_visible: true)
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: deliverable.order_item,
                                     kind: :final, status: :ready, storage_key: "portal-types/hidden.jpg",
                                     filename: "hidden.jpg", content_type: "image/jpeg", byte_size: 5,
                                     customer_visible: false, hidden: true)

    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    portal_deliverable = response.parsed_body.fetch("deliverables").find { |entry| entry["id"] == deliverable.id }
    expect(portal_deliverable).to include("asset_count" => 0, "assets" => [], "status" => "delivered")
  end
end
