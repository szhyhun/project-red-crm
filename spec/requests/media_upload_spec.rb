require "rails_helper"
require "tempfile"

RSpec.describe "Media uploads", type: :request do
  it "stores an internal final upload as pending and enqueues verification" do
    organization = Organization.create!(name: "Upload Agency", slug: "upload-agency")
    manager = User.create!(organization: organization, name: "Manager", email: "manager-upload@example.test", password: "long-enough-password", role: :manager)
    client = ClientAccount.create!(organization: organization, name: "Agent", kind: :agent)
    listing = Listing.create!(organization: organization, client_account: client, address_line_1: "20 Delivery Street")
    upload = Tempfile.new([ "delivery", ".txt" ])
    upload.write("final delivery")
    upload.rewind
    file = Rack::Test::UploadedFile.new(upload.path, "text/plain", true, original_filename: "delivery.txt")

    allow(MediaAssets::VerifyUploadJob).to receive(:perform_later)
    sign_in manager
    post "/api/v1/media_assets/upload", params: { listing_id: listing.id, kind: "final", file: file }

    expect(response).to have_http_status(:created)
    asset = MediaAsset.order(:id).last
    expect(asset).to be_pending
    expect(asset.storage_key).to include("organizations/#{organization.id}/listings/#{listing.id}/")
    expect(DeliveryStorage).to exist(asset.storage_key)
    expect(MediaAssets::VerifyUploadJob).to have_received(:perform_later).with(asset.id)
  ensure
    upload&.close!
  end

  it "marks the media record failed when storage cannot write the upload" do
    organization = Organization.create!(name: "Failed Upload Agency", slug: "failed-upload-agency")
    manager = User.create!(organization:, name: "Manager", email: "failed-upload@example.test", password: "long-enough-password", role: :manager)
    client = ClientAccount.create!(organization:, name: "Agent", kind: :agent)
    listing = Listing.create!(organization:, client_account: client, address_line_1: "21 Delivery Street")
    upload = Tempfile.new([ "delivery", ".txt" ])
    file = Rack::Test::UploadedFile.new(upload.path, "text/plain", true, original_filename: "delivery.txt")
    allow(DeliveryStorage).to receive(:write).and_raise(DeliveryStorage::WriteError, "disk full")
    sign_in manager

    post "/api/v1/media_assets/upload", params: { listing_id: listing.id, kind: "final", file: file }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(MediaAsset.order(:id).last).to have_attributes(status: "failed", metadata: include("processing_error" => "disk full"))
  ensure
    upload&.close!
  end

  it "downloads uploaded media as an attachment" do
    organization = Organization.create!(name: "Download Agency", slug: "download-agency")
    manager = User.create!(organization:, name: "Manager", email: "download@example.test", password: "long-enough-password", role: :manager)
    client = ClientAccount.create!(organization:, name: "Agent", kind: :agent)
    listing = Listing.create!(organization:, client_account: client, address_line_1: "22 Delivery Street")
    key = DeliveryStorage.key_for(organization:, listing:, filename: "unsafe.html")
    tempfile = Tempfile.new([ "unsafe", ".html" ])
    tempfile.write("<script>alert('unsafe')</script>")
    tempfile.rewind
    DeliveryStorage.write(upload: tempfile, key: key)
    asset = MediaAsset.create!(organization:, listing:, uploaded_by: manager, kind: :final, status: :ready, storage_key: key, filename: "unsafe.html", content_type: "text/html")
    sign_in manager

    get "/api/v1/media_assets/#{asset.id}/download"

    expect(response).to have_http_status(:ok)
    expect(response.headers.fetch("Content-Disposition")).to include("attachment")
    expect(response.media_type).to eq("application/octet-stream")
  ensure
    tempfile&.close!
  end

  it "uploads multiple delivery files in one request" do
    organization = Organization.create!(name: "Batch Upload Agency", slug: "batch-upload-agency")
    manager = User.create!(organization:, name: "Manager", email: "batch-upload@example.test", password: "long-enough-password", role: :manager)
    client = ClientAccount.create!(organization:, name: "Agent", kind: :agent)
    listing = Listing.create!(organization:, client_account: client, address_line_1: "23 Delivery Street")
    uploads = %w[first second].map do |name|
      tempfile = Tempfile.new([ name, ".txt" ])
      tempfile.write(name)
      tempfile.rewind
      [ tempfile, Rack::Test::UploadedFile.new(tempfile.path, "text/plain", true, original_filename: "#{name}.txt") ]
    end
    allow(MediaAssets::VerifyUploadJob).to receive(:perform_later)
    sign_in manager

    post "/api/v1/media_assets/upload", params: { listing_id: listing.id, kind: "final", files: uploads.map(&:last) }

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch("media_assets").pluck("filename")).to contain_exactly("first.txt", "second.txt")
    expect(listing.media_assets.count).to eq(2)
  ensure
    uploads&.each { |tempfile, _file| tempfile.close! }
  end

  it "registers an external media link without creating a local download" do
    organization = Organization.create!(name: "Link Agency", slug: "link-agency")
    manager = User.create!(organization:, name: "Manager", email: "link@example.test", password: "long-enough-password", role: :manager)
    client = ClientAccount.create!(organization:, name: "Agent", kind: :agent)
    listing = Listing.create!(organization:, client_account: client, address_line_1: "25 Delivery Street")
    sign_in manager

    post "/api/v1/media_assets/link", params: {
      listing_id: listing.id,
      source_url: "https://example.test/tour/25-delivery",
      filename: "Matterport tour",
      content_type: "text/html",
      category: "tours",
      customer_visible: true
    }

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch("media_asset")).to include(
      "status" => "ready",
      "source_url" => "https://example.test/tour/25-delivery",
      "cdn_url" => "https://example.test/tour/25-delivery",
      "download_path" => nil
    )
    expect(MediaAsset.order(:id).last).to be_external
  end

  it "replaces an existing delivery file and queues verification" do
    organization = Organization.create!(name: "Replace Agency", slug: "replace-agency")
    manager = User.create!(organization:, name: "Manager", email: "replace@example.test", password: "long-enough-password", role: :manager)
    client = ClientAccount.create!(organization:, name: "Agent", kind: :agent)
    listing = Listing.create!(organization:, client_account: client, address_line_1: "24 Delivery Street")
    old_file = Tempfile.new([ "old", ".txt"])
    old_file.write("old")
    old_file.rewind
    old_key = DeliveryStorage.key_for(organization:, listing:, filename: "old.txt")
    DeliveryStorage.write(upload: old_file, key: old_key)
    asset = MediaAsset.create!(organization:, listing:, uploaded_by: manager, kind: :final, status: :ready, storage_key: old_key, filename: "old.txt", content_type: "text/plain")
    new_file = Tempfile.new([ "new", ".txt"])
    new_file.write("new")
    new_file.rewind
    allow(MediaAssets::VerifyUploadJob).to receive(:perform_later)
    sign_in manager

    post "/api/v1/media_assets/#{asset.id}/replace", params: { file: Rack::Test::UploadedFile.new(new_file.path, "text/plain", true, original_filename: "new.txt") }

    expect(response).to have_http_status(:ok)
    expect(asset.reload).to have_attributes(filename: "new.txt", status: "pending")
    expect(DeliveryStorage).not_to exist(old_key)
    expect(DeliveryStorage).to exist(asset.storage_key)
    expect(MediaAssets::VerifyUploadJob).to have_received(:perform_later).with(asset.id)
  ensure
    old_file&.close!
    new_file&.close!
  end

  it "keeps batch positions and updates media metadata" do
    organization = Organization.create!(name: "Metadata Agency", slug: "metadata-agency")
    manager = User.create!(organization:, name: "Manager", email: "metadata@example.test", password: "long-enough-password", role: :manager)
    client = ClientAccount.create!(organization:, name: "Agent", kind: :agent)
    listing = Listing.create!(organization:, client_account: client, address_line_1: "26 Delivery Street")
    uploads = 2.times.map do |index|
      file = Tempfile.new([ "image-#{index}", ".jpg"])
      file.write("image-#{index}")
      file.rewind
      [file, Rack::Test::UploadedFile.new(file.path, "image/jpeg", true, original_filename: "image-#{index}.jpg")]
    end
    allow(MediaAssets::VerifyUploadJob).to receive(:perform_later)
    sign_in manager

    post "/api/v1/media_assets/upload", params: { listing_id: listing.id, kind: "final", category: "images", files: uploads.map(&:last) }
    expect(response).to have_http_status(:created)
    expect(listing.media_assets.order(:position).pluck(:position)).to eq([1, 2])

    asset = listing.media_assets.first
    sign_in manager
    patch "/api/v1/media_assets/#{asset.id}", params: { media_asset: { metadata: { description: "Front elevation", thumbnail_url: "https://example.test/poster.jpg" } } }
    expect(response).to have_http_status(:ok)
    expect(asset.reload.metadata).to include("description" => "Front elevation", "thumbnail_url" => "https://example.test/poster.jpg")
    expect(listing.activity_events.order(:id).last.payload).to include("media_asset_id" => asset.id, "category" => "images")
  ensure
    uploads&.each { |tempfile, _file| tempfile.close! }
  end

  it "records the source order and item for uploaded media" do
    organization = Organization.create!(name: "Source Agency", slug: "source-agency")
    manager = User.create!(organization:, name: "Manager", email: "source@example.test", password: "long-enough-password", role: :manager)
    client = ClientAccount.create!(organization:, name: "Agent", kind: :agent)
    listing = Listing.create!(organization:, client_account: client, address_line_1: "27 Delivery Street")
    order = Order.create!(organization:, client_account: client, listing:, payment_mode: :pay_later)
    item = order.order_items.create!(title: "Premium Photos", quantity: 1, unit_price_cents: 45000, total_cents: 45000)
    upload = Tempfile.new([ "source", ".jpg" ])
    upload.write("image")
    upload.rewind
    allow(MediaAssets::VerifyUploadJob).to receive(:perform_later)
    sign_in manager

    post "/api/v1/media_assets/upload", params: {
      listing_id: listing.id,
      order_id: order.id,
      order_item_id: item.id,
      category: "images",
      file: Rack::Test::UploadedFile.new(upload.path, "image/jpeg", true, original_filename: "source.jpg")
    }

    expect(response).to have_http_status(:created)
    asset = MediaAsset.order(:id).last
    expect(asset).to have_attributes(order_id: order.id, order_item_id: item.id)
    expect(response.parsed_body.fetch("media_asset")).to include("order_id" => order.id, "order_item_id" => item.id)
    expect(listing.activity_events.order(:id).last.payload).to include("order_id" => order.id, "order_item_id" => item.id)
  ensure
    upload&.close!
  end
end
