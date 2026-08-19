require "rails_helper"

RSpec.describe AryeoMediaCopyJob, type: :job do
  it "marks a copied Aryeo media record complete" do
    organization = Organization.create!(name: "Media Import", slug: "media-import")
    client = ClientAccount.create!(organization:, name: "Agent")
    listing = Listing.create!(organization:, client_account: client, address_line_1: "20 Copy Street")
    connection = IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
    asset = MediaAsset.create!(organization:, listing:, filename: "tour.mp4", content_type: "video/mp4", storage_key: "imports/tour.mp4", status: :pending)
    external_record = ExternalRecord.create!(organization:, integration_connection: connection, provider: :aryeo, resource_type: "media_assets", external_id: "media-1", record: asset, sync_status: :pending_media_copy, metadata: { "media_url" => "https://example.test/tour.mp4" })

    expect(Aryeo::RemoteMediaCopy).to receive(:call).with(asset:, source_url: "https://example.test/tour.mp4")
    described_class.perform_now(external_record.id)

    expect(external_record.reload).to be_copied
  end
end
