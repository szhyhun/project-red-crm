require "rails_helper"

RSpec.describe "Media delivery mutations API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Media mutation agency", slug: "media-mutation-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Media mutation manager", email: "media-mutation-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Media mutation client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Media mutation customer", email: "media-mutation-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "31 Media Mutation Street") }
  let!(:other_listing) { Listing.create!(organization:, client_account:, address_line_1: "32 Other Media Street") }
  let!(:service) do
    organization.products.create!(slug: "media-mutation-service", title: "Mutation photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:order) { create_order(listing) }
  let!(:deliverable) { materialize(order) }
  let!(:other_order) { create_order(other_listing) }
  let!(:other_deliverable) { materialize(other_order) }

  before { sign_in manager }

  it "links, orders, and delivers existing media without creating catalog records" do
    product_count = Product.count
    variant_count = ProductVariant.count
    first = link_asset("first.jpg")
    second = link_asset("second.jpg")

    expect([ first, second ].map { |asset| asset.category }).to all(eq("images"))
    expect([ first, second ].map { |asset| asset.status }).to all(eq("ready"))

    post "/api/v1/media_assets/reorder", params: {
      listing_id: listing.id,
      order_deliverable_id: deliverable.id,
      category: "images",
      asset_ids: [ second.id, first.id ]
    }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("media_assets").pluck("id")).to eq([ second.id, first.id ])
    expect(deliverable.media_assets.order(:position).pluck(:id)).to eq([ second.id, first.id ])

    sign_out manager
    sign_in client_user
    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("deliverables", 0, "assets").pluck("filename")).to eq([ "second.jpg", "first.jpg" ])
    expect(response.parsed_body.dig("deliverables", 0, "assets")).to all(satisfy { |asset|
      asset.keys.none? { |key| %w[storage_key source_url customer_visible hidden].include?(key) }
    })
    expect(Product.count).to eq(product_count)
    expect(ProductVariant.count).to eq(variant_count)
  end

  it "attaches an unassigned asset to an existing deliverable through the API" do
    asset = listing.media_assets.create!(organization:, kind: :final, status: :ready,
                                         source_url: "https://cdn.example.test/unassigned.jpg",
                                         filename: "unassigned.jpg", content_type: "image/jpeg", byte_size: 5)

    patch "/api/v1/media_assets/#{asset.id}", params: {
      media_asset: { order_deliverable_id: deliverable.id }
    }

    expect(response).to have_http_status(:ok)
    expect(asset.reload).to have_attributes(order_deliverable: deliverable, category: "images")
    expect(response.parsed_body.fetch("media_asset")).to include("order_deliverable_id" => deliverable.id)
  end

  it "rejects moving an asset into a deliverable for another listing" do
    asset = listing.media_assets.create!(organization:, kind: :final, status: :ready,
                                         source_url: "https://cdn.example.test/lineage.jpg",
                                         filename: "lineage.jpg", content_type: "image/jpeg", byte_size: 5)

    patch "/api/v1/media_assets/#{asset.id}", params: {
      media_asset: { order_deliverable_id: other_deliverable.id }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(asset.reload.order_deliverable_id).to be_nil
  end

  it "rejects a reorder payload that mixes assets from another deliverable" do
    first = link_asset("owned.jpg")
    foreign = MediaAsset.create!(organization:, listing: other_listing, order: other_order,
                                 order_item: other_order.order_items.sole, order_deliverable: other_deliverable,
                                 kind: :final, status: :ready, source_url: "https://cdn.example.test/foreign.jpg",
                                 filename: "foreign.jpg", content_type: "image/jpeg", byte_size: 5)

    post "/api/v1/media_assets/reorder", params: {
      listing_id: listing.id,
      order_deliverable_id: deliverable.id,
      category: "images",
      asset_ids: [ first.id, foreign.id ]
    }

    expect(response).to have_http_status(:not_found)
    expect(first.reload.position).not_to eq(1)
  end

  it "does not let a customer update or delete staff-managed media" do
    asset = link_asset("staff-managed.jpg")
    allow(DeliveryStorage).to receive(:delete)
    sign_out manager
    sign_in client_user

    patch "/api/v1/media_assets/#{asset.id}", params: { media_asset: { filename: "forged.jpg" } }
    expect(response).to have_http_status(:forbidden)

    delete "/api/v1/media_assets/#{asset.id}"
    expect(response).to have_http_status(:forbidden)
    expect(MediaAsset).to exist(asset.id)
    expect(DeliveryStorage).not_to have_received(:delete)
  end

  private

  def create_order(listing)
    Orders::Creator.new(organization:, attributes: {
      client_account_id: client_account.id,
      listing_id: listing.id,
      payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).create!.tap { |record| record.update!(status: :approved, approved_at: Time.current) }
  end

  def materialize(order)
    Orders::DeliverableMaterializer.new(order:).call.sole
  end

  def link_asset(filename)
    post "/api/v1/media_assets/link", params: {
      listing_id: listing.id,
      order_deliverable_id: deliverable.id,
      source_url: "https://cdn.example.test/#{filename}",
      filename:,
      content_type: "image/jpeg",
      category: "files",
      customer_visible: true
    }

    expect(response).to have_http_status(:created)
    MediaAsset.find(response.parsed_body.dig("media_asset", "id"))
  end
end
