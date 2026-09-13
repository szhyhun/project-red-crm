require "rails_helper"
require "tempfile"

RSpec.describe "Deliverable media API", type: :request do
  let!(:organization) { Organization.create!(name: "Deliverable Media Agency", slug: "deliverable-media-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Media Agency", slug: "other-media-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Media Manager", email: "deliverable-media-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Media Client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Media Client User", email: "deliverable-media-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "4 Media Street") }
  let!(:service) do
    Product.create!(organization:, slug: "media-photo-service", title: "Media photography", kind: :service,
                    deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
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

  it "links an external asset to a deliverable without exposing a CDN field" do
    sign_in manager

    post "/api/v1/media_assets/link", params: {
      listing_id: listing.id,
      order_deliverable_id: deliverable.id,
      source_url: "https://vendor.example.test/photo-tour",
      filename: "Photo tour",
      content_type: "text/html",
      category: "tours",
      customer_visible: true
    }

    expect(response).to have_http_status(:created)
    asset = MediaAsset.order(:id).last
    expect(asset).to have_attributes(order_id: order.id, order_item_id: order.order_items.sole.id,
                                     order_deliverable_id: deliverable.id, status: "ready")
    expect(response.parsed_body.fetch("media_asset")).to include(
      "order_deliverable_id" => deliverable.id, "cdn_url" => nil, "preview_path" => nil
    )
  end

  it "uploads a file to the delivery boundary while retaining deliverable lineage" do
    upload = Tempfile.new([ "deliverable", ".jpg" ])
    upload.write("image bytes")
    upload.rewind
    allow(MediaAssets::VerifyUploadJob).to receive(:perform_later)
    sign_in manager

    post "/api/v1/media_assets/upload", params: {
      listing_id: listing.id,
      order_deliverable_id: deliverable.id,
      file: Rack::Test::UploadedFile.new(upload.path, "image/jpeg", true, original_filename: "front.jpg")
    }

    expect(response).to have_http_status(:created)
    asset = MediaAsset.order(:id).last
    expect(asset).to have_attributes(order_id: order.id, order_item_id: order.order_items.sole.id,
                                     order_deliverable_id: deliverable.id, category: "images")
    expect(response.parsed_body.fetch("media_asset")).not_to have_key("storage_key")
  ensure
    upload&.close!
  end

  it "rejects a deliverable from another order when registering an asset" do
    other_client = ClientAccount.create!(organization:, name: "Second Media Client", kind: :agent)
    other_listing = Listing.create!(organization:, client_account: other_client, address_line_1: "5 Media Street")
    other_product = organization.products.create!(slug: "second-media-service", title: "Second service", kind: :service,
                                                   deliverable_type: "video")
    other_variant = other_product.product_variants.create!(title: "Standard", price_cents: 10_000)
    other_order = Orders::Create.call(
      organization:,
      attributes: {
        client_account_id: other_client.id,
        listing_id: other_listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: other_variant.id, quantity: 1 } ]
      }
    ).fetch(:order)
    other_order.update!(status: :approved, approved_at: Time.current)
    other_deliverable = Orders::DeliverableMaterializer.new(order: other_order).call.sole
    sign_in manager

    post "/api/v1/media_assets/link", params: {
      listing_id: listing.id,
      order_deliverable_id: other_deliverable.id,
      source_url: "https://vendor.example.test/foreign",
      filename: "Foreign asset",
      content_type: "text/html"
    }

    expect(response).to have_http_status(:not_found)
    expect(MediaAsset.where(source_url: "https://vendor.example.test/foreign")).to be_empty
  end

  it "rejects changing an asset to a different deliverable" do
    second_service = organization.products.create!(slug: "second-deliverable-service", title: "Second deliverable",
                                                    kind: :service, deliverable_type: "video")
    second_variant = second_service.product_variants.create!(title: "Standard", price_cents: 10_000)
    second_order = Orders::Create.call(
      organization:,
      attributes: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: second_variant.id, quantity: 1 } ]
      }
    ).fetch(:order)
    second_order.update!(status: :approved, approved_at: Time.current)
    second_deliverable = Orders::DeliverableMaterializer.new(order: second_order).call.sole
    asset = deliverable.media_assets.create!(organization:, listing:, kind: :final, status: :ready,
                                              storage_key: "deliverable-media/original.jpg", filename: "original.jpg",
                                              content_type: "image/jpeg")
    sign_in manager

    patch "/api/v1/media_assets/#{asset.id}", params: {
      media_asset: { order_deliverable_id: second_deliverable.id }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(asset.reload.order_deliverable_id).to eq(deliverable.id)
  end

  it "returns private API paths to an authorized customer and hides staff-only media" do
    visible = deliverable.media_assets.create!(organization:, listing:, kind: :final, status: :ready,
                                                storage_key: "deliverable-media/visible.jpg", filename: "visible.jpg",
                                                content_type: "image/jpeg", customer_visible: true)
    hidden = deliverable.media_assets.create!(organization:, listing:, kind: :final, status: :ready,
                                               storage_key: "deliverable-media/hidden.jpg", filename: "hidden.jpg",
                                               content_type: "image/jpeg", customer_visible: false)
    sign_in client_user

    get "/api/v1/media_assets", params: { listing_id: listing.id }

    expect(response).to have_http_status(:ok)
    assets = response.parsed_body.fetch("media_assets")
    expect(assets.pluck("id")).to contain_exactly(visible.id)
    expect(assets.sole).to include(
      "preview_path" => "/api/v1/media_assets/#{visible.id}/preview",
      "download_path" => "/api/v1/media_assets/#{visible.id}/download"
    )
    expect(assets.sole).not_to have_key("storage_key")
    expect(hidden).to be_persisted
  end

  it "does not allow a customer to preview another organization's asset" do
    other_client = ClientAccount.create!(organization: other_organization, name: "Other Client", kind: :agent)
    other_listing = Listing.create!(organization: other_organization, client_account: other_client,
                                    address_line_1: "Other Media Street")
    other_asset = MediaAsset.create!(organization: other_organization, listing: other_listing, kind: :final,
                                     status: :ready, storage_key: "other-media/private.jpg", filename: "private.jpg",
                                     content_type: "image/jpeg", customer_visible: true)
    sign_in client_user

    get "/api/v1/media_assets/#{other_asset.id}/preview"

    expect(response).to have_http_status(:not_found)
  end

  it "reorders only assets attached to the selected deliverable" do
    first = deliverable.media_assets.create!(organization:, listing:, kind: :final, status: :ready,
                                              storage_key: "deliverable-media/first.jpg", filename: "first.jpg",
                                              content_type: "image/jpeg", position: 0)
    second = deliverable.media_assets.create!(organization:, listing:, kind: :final, status: :ready,
                                               storage_key: "deliverable-media/second.jpg", filename: "second.jpg",
                                               content_type: "image/jpeg", position: 1)
    unrelated = listing.media_assets.create!(organization:, kind: :final, status: :ready,
                                             storage_key: "listing-media/unrelated.jpg", filename: "unrelated.jpg",
                                             content_type: "image/jpeg", category: "images", position: 0)
    sign_in manager

    post "/api/v1/media_assets/reorder", params: {
      listing_id: listing.id,
      category: "images",
      order_deliverable_id: deliverable.id,
      asset_ids: [ second.id, first.id ]
    }

    expect(response).to have_http_status(:ok)
    expect(first.reload.position).to eq(1)
    expect(second.reload.position).to eq(0)
    expect(unrelated.reload.position).to eq(0)
    expect(response.parsed_body.fetch("media_assets").pluck("id")).to eq([ second.id, first.id ])
  end
end
