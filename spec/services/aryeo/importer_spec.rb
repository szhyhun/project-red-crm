require "rails_helper"

RSpec.describe Aryeo::Importer do
  let!(:organization) { Organization.create!(name: "Import Agency", slug: "import-agency") }
  let!(:connection) { IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected) }

  def import_run
    connection.integration_import_runs.create!(organization:, provider: :aryeo)
  end

  def client_with_catalog
    instance_double(Aryeo::Client).tap do |client|
      allow(client).to receive(:paginate) do |endpoint, &block|
        case endpoint
        when "customers"
          block.call({ "id" => "customer-1", "name" => "Avery Agent", "email" => "avery@example.test" })
        when "products"
          block.call({ "id" => "product-1", "title" => "Premium photos", "category_names" => [ "Photo" ],
                       "variants" => [{ "id" => "variant-1", "title" => "Up to 2,000 sqft", "price" => 549 }] })
        when "listings"
          block.call({ "id" => "listing-1", "customer_id" => "customer-1", "address" => { "address_line_1" => "111 Oak Bay Ave", "city" => "Victoria", "province" => "BC" } })
        when "orders"
          block.call({ "id" => "order-1", "listing_id" => "listing-1", "customer_id" => "customer-1", "status" => "submitted", "total" => 549,
                       "items" => [{ "id" => "item-1", "title" => "Premium photos", "quantity" => 1, "price" => 549 }] })
        end
      end
    end
  end

  it "upserts mapped records, preserves Aryeo provenance, and keeps unrelated local records" do
    local_client = ClientAccount.create!(organization:, name: "Local agent")
    local_listing = Listing.create!(organization:, client_account: local_client, address_line_1: "Local Street")

    described_class.new(run: import_run, client: client_with_catalog).call
    described_class.new(run: import_run, client: client_with_catalog).call

    expect(Product.where(origin: "aryeo").count).to eq(1)
    expect(Product.first.product_variants.count).to eq(1)
    expect(Listing.where(origin: "aryeo").pluck(:address_line_1)).to include("111 Oak Bay Ave")
    expect(Order.where(origin: "aryeo").count).to eq(1)
    expect(Order.first.order_items.count).to eq(1)
    expect(ExternalRecord.where(provider: "aryeo").count).to be >= 4
    expect(Listing.find(local_listing.id)).to be_present
  end

  it "keeps a limited development migration to the most recently changed listings" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate) do |endpoint, &block|
      next unless endpoint == "listings"

      block.call({ "id" => "older-listing", "updated_at" => "2025-01-01T00:00:00Z", "address" => { "address_line_1" => "Older Street" } })
      block.call({ "id" => "newer-listing", "updated_at" => "2026-01-01T00:00:00Z", "address" => { "address_line_1" => "Newer Street" } })
    end

    described_class.new(run: import_run, client:, listing_limit: 1).call

    expect(Listing.where(origin: "aryeo").pluck(:address_line_1)).to contain_exactly("Newer Street")
  end

  it "can skip listing and media-bearing resources for a metadata-only import" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate) do |endpoint, &block|
      block.call({ "id" => "product-1", "title" => "Premium photos" }) if endpoint == "products"
    end

    described_class.new(run: import_run, client:, skip_resources: [ :listings ]).call

    expect(client).not_to have_received(:paginate).with("listings")
    expect(connection.reload.endpoint_coverage).to include("listings" => include("status" => "skipped"))
    expect(Product.where(origin: "aryeo").count).to eq(1)
  end
end
