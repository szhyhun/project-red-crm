require "rails_helper"

RSpec.describe AryeoMediaCopyJob, type: :job do
  it "marks a copied Aryeo media record complete" do
    organization = Organization.create!(name: "Media Import", slug: "media-import")
    client = ClientAccount.create!(organization:, name: "Agent")
    listing = Listing.create!(organization:, client_account: client, address_line_1: "20 Copy Street")
    connection = IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
    asset = MediaAsset.create!(organization:, listing:, filename: "tour.mp4", content_type: "video/mp4", storage_key: "imports/tour.mp4", status: :pending)
    external_record = ExternalRecord.create!(organization:, integration_connection: connection, provider: :aryeo, resource_type: "media_assets", external_id: "media-1", record: asset, sync_status: :pending_media_copy, metadata: { "media_url" => "https://example.test/tour.mp4" })

    expect(Aryeo::RemoteMediaCopy).to receive(:call).with(asset:, source_url: "https://example.test/tour.mp4", api_key: "aryeo-key")
    described_class.perform_now(external_record.id)

    expect(external_record.reload).to be_copied
  end

  it "marks the asset and external record failed after the final retry" do
    organization = Organization.create!(name: "Media Import Retry", slug: "media-import-retry")
    client = ClientAccount.create!(organization:, name: "Agent")
    listing = Listing.create!(organization:, client_account: client, address_line_1: "21 Copy Street")
    connection = IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
    asset = MediaAsset.create!(organization:, listing:, filename: "tour.mp4", content_type: "video/mp4", storage_key: "imports/retry-tour.mp4", status: :pending)
    external_record = ExternalRecord.create!(organization:, integration_connection: connection, provider: :aryeo, resource_type: "media_assets", external_id: "media-retry", record: asset, sync_status: :pending_media_copy, metadata: { "media_url" => "https://videos.aryeo.com/tour.mp4" })

    allow(Aryeo::RemoteMediaCopy).to receive(:call).and_raise(Aryeo::RemoteMediaCopy::RetryableError, "download failed")
    job = described_class.new
    allow(job).to receive(:executions).and_return(5)

    expect { job.perform(external_record.id) }.to raise_error(Aryeo::RemoteMediaCopy::RetryableError)

    expect(external_record.reload).to have_attributes(sync_status: "failed", metadata: include("media_copy_error" => "media_copy_failed"))
    expect(asset.reload).to have_attributes(status: "failed", metadata: include("processing_error" => "media_copy_failed"))
  end
end
