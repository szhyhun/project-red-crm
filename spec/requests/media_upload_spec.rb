require "rails_helper"
require "tempfile"

RSpec.describe "Media uploads", type: :request do
  it "stores an internal final upload as pending and enqueues verification" do
    organization = Organization.create!(name: "Upload Agency", slug: "upload-agency")
    manager = User.create!(organization: organization, name: "Manager", email: "manager-upload@example.test", password: "long-enough-password", role: :manager)
    client = ClientAccount.create!(organization: organization, name: "Agent", kind: :agent)
    listing = Listing.create!(organization: organization, client_account: client, address_line_1: "20 Delivery Street")
    upload = Tempfile.new(["delivery", ".txt"])
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
    upload = Tempfile.new(["delivery", ".txt"])
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
    tempfile = Tempfile.new(["unsafe", ".html"])
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
end
