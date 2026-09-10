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

  it "honors Aryeo's last_page pagination metadata" do
    client = described_class.new(api_key: "aryeo-key")
    first_page = { "data" => [ { "id" => "one" } ], "meta" => { "current_page" => 1, "last_page" => 2 } }
    second_page = { "data" => [ { "id" => "two" } ], "meta" => { "current_page" => 2, "last_page" => 2 } }

    allow(client).to receive(:get).and_return(first_page, second_page)

    expect { |block| client.paginate("products", per_page: 1, &block) }.to yield_successive_args({ "id" => "one" }, { "id" => "two" })
    expect(client).to have_received(:get).with("products", params: { page: 2, per_page: 1 })
  end

  it "treats a hash data payload as one record instead of iterating its keys" do
    client = described_class.new(api_key: "aryeo-key")
    allow(client).to receive(:get).and_return({ "data" => { "id" => "listing-1", "address" => { "address_line_1" => "Oak Bay Ave" } } })

    expect { |block| client.paginate("listings", &block) }.to yield_with_args(
      "id" => "listing-1", "address" => { "address_line_1" => "Oak Bay Ave" }
    )
  end

  it "unwraps a named collection nested inside the data payload" do
    client = described_class.new(api_key: "aryeo-key")
    allow(client).to receive(:get).and_return({ "data" => { "listings" => [ { "id" => "listing-1" } ] } })

    expect { |block| client.paginate("listings", &block) }.to yield_with_args({ "id" => "listing-1" })
  end
end
