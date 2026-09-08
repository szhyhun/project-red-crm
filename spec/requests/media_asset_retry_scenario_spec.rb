require "rails_helper"

RSpec.describe "Media asset retry API scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Retry media agency", slug: "retry-media-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Retry manager", email: "retry-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_user) do
    User.create!(organization:, name: "Retry client", email: "retry-client@example.test",
                 password: "long-enough-password", role: :client_admin)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Retry client account", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "30 Retry Street") }
  let!(:asset) do
    listing.media_assets.create!(organization:, kind: :final, status: :failed,
                                 storage_key: "organizations/#{organization.id}/listings/#{listing.id}/retry.jpg",
                                 filename: "retry.jpg", content_type: "image/jpeg", byte_size: 5,
                                 metadata: { "processing_error" => "upload_missing" })
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    ClientMembership.create!(client_account:, user: client_user, role: :admin)
  end

  it "resets a failed asset and completes verification through the queued job" do
    allow(DeliveryStorage).to receive(:exist?).with(asset.storage_key).and_return(true)
    sign_in manager

    perform_enqueued_jobs(only: MediaAssets::VerifyUploadJob) do
      post "/api/v1/media_assets/#{asset.id}/retry"
    end

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("media_asset")).to include(
      "id" => asset.id,
      "status" => "pending",
      "preview_path" => nil,
      "download_path" => nil
    )
    expect(asset.reload).to have_attributes(status: "ready", processed_at: be_present)
    expect(asset.metadata).not_to have_key("processing_error")

    get "/api/v1/media_assets", params: { listing_id: listing.id }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("media_assets")).to include(
      include(
        "id" => asset.id,
        "status" => "ready",
        "preview_path" => "/api/v1/media_assets/#{asset.id}/preview",
        "download_path" => "/api/v1/media_assets/#{asset.id}/download"
      )
    )
  end

  it "keeps customers from retrying staff media processing" do
    sign_in client_user

    post "/api/v1/media_assets/#{asset.id}/retry"

    # Failed assets are not in the customer policy scope at all, so the API
    # deliberately answers as if the private record does not exist.
    expect(response).to have_http_status(:not_found)
    expect(asset.reload).to be_failed
    expect(enqueued_jobs).to be_empty
  end
end
