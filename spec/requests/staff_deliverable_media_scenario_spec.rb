require "rails_helper"
require "tempfile"

RSpec.describe "Staff deliverable media API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Staff media agency", slug: "staff-media-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Staff media manager", email: "staff-media-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Staff media client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "60 Staff Media Street") }
  let!(:service) do
    organization.products.create!(slug: "staff-media-service", title: "Standard property photography",
                                  kind: :service, deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 32_000) }
  let!(:order) do
    Orders::Create.call(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).fetch(:order)
  end
  let!(:deliverable) do
    order.update!(status: :approved, approved_at: Time.current)
    Orders::DeliverableMaterializer.new(order:).call.sole
  end

  before do
    allow(MediaAssets::VerifyUploadJob).to receive(:perform_later)
    sign_in manager
  end

  it "uploads directly to an existing deliverable without changing catalog records" do
    upload = Tempfile.new([ "staff-deliverable", ".jpg" ])
    upload.write("image bytes")
    upload.rewind
    allow(DeliveryStorage).to receive(:write)
    product_count = Product.count
    variant_count = ProductVariant.count

    post "/api/v1/media_assets/upload", params: {
      listing_id: listing.id,
      order_deliverable_id: deliverable.id,
      file: Rack::Test::UploadedFile.new(upload.path, "image/jpeg", true, original_filename: "front.jpg")
    }

    expect(response).to have_http_status(:created)
    asset = deliverable.media_assets.sole
    expect(asset).to have_attributes(
      order_id: order.id,
      order_item_id: order.order_items.sole.id,
      category: "images",
      status: "pending",
      order_deliverable_id: deliverable.id
    )
    expect(Product.count).to eq(product_count)
    expect(ProductVariant.count).to eq(variant_count)
    expect(response.parsed_body.fetch("media_asset")).to include(
      "order_deliverable_id" => deliverable.id,
      "preview_path" => nil,
      "download_path" => nil
    )
    expect(response.parsed_body.fetch("media_asset")).not_to have_key("storage_key")
    expect(MediaAssets::VerifyUploadJob).to have_received(:perform_later).with(asset.id)
  ensure
    upload&.close!
  end

  it "keeps an externally hosted deliverable asset out of the private download boundary" do
    post "/api/v1/media_assets/link", params: {
      listing_id: listing.id,
      order_deliverable_id: deliverable.id,
      source_url: "https://vendor.example.test/photography/front.jpg",
      filename: "front.jpg",
      content_type: "image/jpeg",
      category: "images",
      customer_visible: true
    }

    expect(response).to have_http_status(:created)
    asset = deliverable.media_assets.sole
    expect(asset).to have_attributes(status: "ready", source_url: "https://vendor.example.test/photography/front.jpg")
    expect(response.parsed_body.fetch("media_asset")).to include(
      "cdn_url" => nil,
      "preview_path" => nil,
      "download_path" => nil
    )
  end

  it "does not allow staff to attach a deliverable to a different listing through the upload route" do
    other_account = ClientAccount.create!(organization:, name: "Other staff media client", kind: :agent)
    other_listing = Listing.create!(organization:, client_account: other_account, address_line_1: "61 Private Media Street")
    upload = Tempfile.new([ "wrong-lineage", ".jpg" ])
    upload.write("image bytes")
    upload.rewind
    allow(DeliveryStorage).to receive(:write)

    post "/api/v1/media_assets/upload", params: {
      listing_id: other_listing.id,
      order_deliverable_id: deliverable.id,
      file: Rack::Test::UploadedFile.new(upload.path, "image/jpeg", true, original_filename: "wrong.jpg")
    }

    expect(response).to have_http_status(:not_found)
    expect(MediaAsset.where(filename: "wrong.jpg")).to be_empty
  ensure
    upload&.close!
  end

  it "does not let a customer upload a replacement through the staff media endpoint" do
    client_user = User.create!(organization:, name: "Staff media customer", email: "staff-media-customer@example.test",
                               password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account:, user: client_user, role: :admin)
    sign_out manager
    sign_in client_user

    post "/api/v1/media_assets/upload", params: { listing_id: listing.id }

    expect(response).to have_http_status(:forbidden)
    expect(deliverable.media_assets).to be_empty
  end
end
