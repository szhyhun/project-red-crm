require "rails_helper"

RSpec.describe Aryeo::Client do
  it "rejects non-GET requests before making a network call" do
    client = described_class.new(api_key: "aryeo-key")

    expect(Net::HTTP).not_to receive(:start)
    expect { client.request(:post, "products") }.to raise_error(Aryeo::Client::ReadOnlyViolation)
  end

  it "follows supplied pagination links without issuing a write" do
    client = described_class.new(api_key: "aryeo-key")
    first_page = { "data" => [ { "id" => "one" } ], "links" => { "next" => "/v1/products?page=2" } }
    second_page = { "data" => [ { "id" => "two" } ], "links" => { "next" => nil } }

    allow(client).to receive(:get).and_return(first_page, second_page)

    expect { |block| client.paginate("products", per_page: 1, &block) }.to yield_successive_args({ "id" => "one" }, { "id" => "two" })
    expect(client).to have_received(:get).with("/v1/products?page=2", params: {})
  end
end
