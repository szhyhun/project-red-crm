require "rails_helper"

RSpec.describe MediaAsset, type: :model do
  let!(:organization) { Organization.create!(name: "Asset contract agency", slug: "asset-contract-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Asset client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "1 Asset Street") }

  def build_asset(attributes = {})
    described_class.new({
      organization:, listing:, kind: :final, status: :ready,
      storage_key: "organizations/#{organization.id}/listings/#{listing.id}/asset",
      filename: "asset.jpg", content_type: "image/jpeg", byte_size: 5
    }.merge(attributes))
  end

  it "derives the images category for an uploaded image with the default category" do
    asset = build_asset(category: nil)

    expect(asset).to be_valid
    expect(asset.category).to eq("images")
  end

  it "derives the videos category for an uploaded video with the default category" do
    asset = build_asset(category: "files", filename: "tour.mp4", content_type: "video/mp4")

    expect(asset).to be_valid
    expect(asset.category).to eq("videos")
  end

  it "preserves an explicit deliverable category instead of classifying it from the MIME type" do
    asset = build_asset(category: "floor_plans", filename: "plan.pdf", content_type: "application/pdf")

    expect(asset).to be_valid
    expect(asset.category).to eq("floor_plans")
  end

  it "accepts supported storage types and rejects browser-active document types" do
    expect(described_class.safe_storage_content_type?("image/jpeg")).to be(true)
    expect(described_class.safe_storage_content_type?("video/mp4")).to be(true)
    expect(described_class.safe_storage_content_type?("application/pdf")).to be(true)
    expect(described_class.safe_storage_content_type?("image/svg+xml")).to be(false)
    expect(described_class.safe_storage_content_type?("text/html")).to be(false)
  end

  it "allows safe inline previews but never treats SVG or HTML as inline content" do
    expect(described_class.safe_inline_content_type?("image/jpeg")).to be(true)
    expect(described_class.safe_inline_content_type?("video/mp4")).to be(true)
    expect(described_class.safe_inline_content_type?("image/svg+xml")).to be(false)
    expect(described_class.safe_inline_content_type?("text/html")).to be(false)
  end

  it "requires a private storage key or an HTTPS external source" do
    missing_source = build_asset(storage_key: nil, source_url: nil)
    invalid_source = build_asset(storage_key: nil, source_url: "javascript:alert(1)")
    external_asset = build_asset(storage_key: nil, source_url: "https://cdn.example.test/asset.jpg")

    expect(missing_source).not_to be_valid
    expect(missing_source.errors.full_messages).to include("a storage key or source URL is required")
    expect(invalid_source).not_to be_valid
    expect(invalid_source.errors.full_messages).to include("Source url is invalid")
    expect(external_asset).to be_valid
    expect(external_asset).to be_external
  end
end
