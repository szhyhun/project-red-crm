require "rails_helper"

RSpec.describe MediaAssets::VerifyUpload do
  it "returns a typed failure and marks an absent upload failed" do
    organization = Organization.create!(name: "Verification Agency", slug: "verification-agency")
    client = ClientAccount.create!(organization:, name: "Agent")
    listing = Listing.create!(organization:, client_account: client, address_line_1: "40 Verify Street")
    asset = MediaAsset.create!(organization:, listing:, kind: :final, status: :pending,
                               storage_key: "missing/upload.txt", filename: "upload.txt", content_type: "text/plain")
    allow(DeliveryStorage).to receive(:exist?).with(asset.storage_key).and_return(false)

    result = described_class.call(asset:)

    expect(result).to be_failure
    expect(result.failure.code).to eq("upload_missing")
    expect(asset.reload).to be_failed
  end
end
