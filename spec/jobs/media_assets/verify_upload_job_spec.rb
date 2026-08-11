require "rails_helper"
require "stringio"

RSpec.describe MediaAssets::VerifyUploadJob, type: :job do
  it "marks an existing stored asset ready" do
    organization = Organization.create!(name: "Media Agency", slug: "media-agency")
    client = ClientAccount.create!(organization: organization, name: "Agent", kind: :agent)
    listing = Listing.create!(organization: organization, client_account: client, address_line_1: "30 Ready Street")
    storage_key = DeliveryStorage.key_for(organization: organization, listing: listing, filename: "final.txt")
    asset = MediaAsset.create!(organization: organization, listing: listing, kind: :final, status: :pending, storage_key: storage_key, filename: "final.txt", content_type: "text/plain")
    DeliveryStorage.write(upload: StringIO.new("ready"), key: storage_key)

    described_class.perform_now(asset.id)

    expect(asset.reload).to be_ready
    expect(asset.processed_at).to be_present
  end
end
