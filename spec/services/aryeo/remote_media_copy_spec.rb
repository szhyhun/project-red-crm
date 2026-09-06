require "rails_helper"

RSpec.describe Aryeo::RemoteMediaCopy do
  it "rejects non-HTTPS and private-network media URLs before making a request" do
    asset = instance_double(MediaAsset, storage_key: "organizations/1/listings/1/asset.jpg")

    expect {
      described_class.call(asset:, source_url: "http://127.0.0.1/latest-secret")
    }.to raise_error(described_class::RetryableError, "Aryeo media URL is not allowed")
  end
end
