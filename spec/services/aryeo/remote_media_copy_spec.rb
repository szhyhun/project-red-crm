require "rails_helper"

RSpec.describe Aryeo::RemoteMediaCopy do
  it "rejects non-HTTPS and private-network media URLs before making a request" do
    asset = instance_double(MediaAsset, storage_key: "organizations/1/listings/1/asset.jpg")

    expect {
      described_class.call(asset:, source_url: "http://127.0.0.1/latest-secret")
    }.to raise_error(described_class::RetryableError, "Aryeo media URL is not allowed")
  end

  it "uses the Aryeo bearer token and preserves the downloaded content type" do
    source_url = "https://cdn.aryeo.com/listings/listing-1/front.jpg"
    asset = instance_double(MediaAsset, storage_key: "organizations/1/listings/1/front.jpg", content_type: "image/jpeg", metadata: {})
    response = double("Aryeo media response")
    http = double("Aryeo media connection")

    allow(Resolv).to receive(:getaddresses).with("cdn.aryeo.com").and_return([ "93.184.216.34" ])
    allow(response).to receive(:is_a?) { |type| type == Net::HTTPSuccess }
    allow(response).to receive(:[]).with("content-type").and_return("image/jpeg; charset=binary")
    allow(response).to receive(:read_body) { |&block| block.call("image-data") }
    allow(http).to receive(:request) do |request, &block|
      expect(request["Authorization"]).to eq("Bearer aryeo-key")
      expect(request["Accept"]).to eq("*/*")
      block.call(response)
      response
    end
    allow(Net::HTTP).to receive(:start).with("cdn.aryeo.com", 443, use_ssl: true, open_timeout: 15, read_timeout: 120).and_yield(http)
    allow(DeliveryStorage).to receive(:write) do |upload:, key:, content_type:|
      expect(upload.read).to eq("image-data")
      expect(key).to eq(asset.storage_key)
      expect(content_type).to eq("image/jpeg")
    end
    allow(asset).to receive(:update!)

    described_class.call(asset:, source_url:, api_key: "aryeo-key")

    expect(asset).to have_received(:update!).with(hash_including(status: :ready, source_url: nil))
  end

  it "follows a safe public redirect without forwarding the Aryeo token" do
    source_url = "https://videos.aryeo.com/listings/listing-1/video.mp4"
    redirected_url = "https://storage.example.test/listing-1/video.mp4"
    asset = instance_double(MediaAsset, storage_key: "organizations/1/listings/1/video.mp4", content_type: "video/mp4", metadata: {})
    redirect = double("Aryeo redirect")
    response = double("download response")
    first_http = double("Aryeo media connection")
    second_http = double("redirected media connection")

    allow(Resolv).to receive(:getaddresses).and_return([ "93.184.216.34" ])
    allow(redirect).to receive(:is_a?) { |type| type == Net::HTTPRedirection }
    allow(redirect).to receive(:[]).with("location").and_return(redirected_url)
    allow(response).to receive(:is_a?) { |type| type == Net::HTTPSuccess }
    allow(response).to receive(:[]).with("content-type").and_return("video/mp4")
    allow(response).to receive(:read_body) { |&block| block.call("video-data") }
    allow(first_http).to receive(:request) do |request, &block|
      expect(request["Authorization"]).to eq("Bearer aryeo-key")
      block.call(redirect)
      redirect
    end
    allow(second_http).to receive(:request) do |request, &block|
      expect(request["Authorization"]).to be_nil
      block.call(response)
      response
    end
    http_connections = [ first_http, second_http ]
    allow(Net::HTTP).to receive(:start) { |*_, &block| block.call(http_connections.shift) }
    allow(DeliveryStorage).to receive(:write)
    allow(asset).to receive(:update!)

    described_class.call(asset:, source_url:, api_key: "aryeo-key")

    expect(DeliveryStorage).to have_received(:write).with(hash_including(content_type: "video/mp4"))
  end
end
