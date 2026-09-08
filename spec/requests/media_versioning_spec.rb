require "rails_helper"
require "tempfile"

RSpec.describe "Media versioning API", type: :request do
  let!(:organization) { Organization.create!(name: "Versioning Agency", slug: "versioning-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Versioning Manager", email: "versioning-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Versioning Client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Versioning Client User", email: "versioning-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "7 Versioning Street") }
  let!(:service) do
    organization.products.create!(slug: "versioning-service", title: "Versioned photography", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:order) do
    Orders::Creator.new(organization:, attributes: {
      client_account_id: client_account.id,
      listing_id: listing.id,
      payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).create!
  end
  let!(:deliverable) do
    order.update!(status: :approved, approved_at: Time.current)
    Orders::DeliverableMaterializer.new(order:).call.sole
  end

  it "keeps the old file for staff while exposing only the replacement to customers" do
    old_asset = deliverable.media_assets.create!(
      organization:, listing:, order:, order_item: order.order_items.sole,
      kind: :final, status: :ready, category: :images,
      storage_key: "organizations/#{organization.id}/deliverables/original.jpg",
      filename: "original.jpg", content_type: "image/jpeg", byte_size: 5, customer_visible: true
    )
    upload = Tempfile.new([ "replacement", ".jpg" ])
    upload.write("new image")
    upload.rewind
    allow(DeliveryStorage).to receive(:write)
    allow(DeliveryStorage).to receive(:delete)
    allow(MediaAssets::VerifyUploadJob).to receive(:perform_later)

    sign_in manager
    post "/api/v1/media_assets/#{old_asset.id}/replace", params: {
      file: Rack::Test::UploadedFile.new(upload.path, "image/jpeg", true, original_filename: "replacement.jpg")
    }

    expect(response).to have_http_status(:ok)
    replacement = MediaAsset.find(response.parsed_body.dig("media_asset", "id"))
    expect(old_asset.reload).to have_attributes(version: 1, status: "ready", superseded_by: replacement)
    expect(replacement).to have_attributes(version: 2, status: "pending", superseded_by_id: nil)
    expect(DeliveryStorage).not_to have_received(:delete).with(old_asset.storage_key)

    replacement.update!(status: :ready)
    sign_out manager
    sign_in client_user

    get "/api/v1/media_assets", params: { listing_id: listing.id }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("media_assets").pluck("id")).to eq([ replacement.id ])

    get "/api/v1/media_assets/#{old_asset.id}/preview"
    expect(response).to have_http_status(:not_found)
  ensure
    upload&.close!
  end

  it "keeps version history visible to staff without exposing storage keys" do
    first = deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                             kind: :final, status: :ready, category: :images,
                                             storage_key: "version-history/first.jpg", filename: "first.jpg",
                                             content_type: "image/jpeg", byte_size: 5)
    second = deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                              kind: :final, status: :ready, category: :images, version: 2,
                                              storage_key: "version-history/second.jpg", filename: "second.jpg",
                                              content_type: "image/jpeg", byte_size: 5)
    first.update!(superseded_by: second)

    sign_in manager
    get "/api/v1/media_assets", params: { listing_id: listing.id }

    expect(response).to have_http_status(:ok)
    assets = response.parsed_body.fetch("media_assets")
    expect(assets.pluck("id")).to contain_exactly(first.id, second.id)
    expect(assets).to all(satisfy { |asset| !asset.key?("storage_key") })
    expect(assets.find { |asset| asset["id"] == first.id }).to include("superseded_by_id" => second.id, "version" => 1)
  end
end
