require "rails_helper"

RSpec.describe Aryeo::Importer do
  let!(:organization) { Organization.create!(name: "Import Agency", slug: "import-agency") }
  let!(:connection) { IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected) }

  def import_run(resources: Aryeo::Importer::RESOURCE_KEYS, conflict_resolution: "skip")
    connection.integration_import_runs.create!(organization:, provider: :aryeo, requested_resources: resources, conflict_resolution:)
  end

  def client_with_catalog
    instance_double(Aryeo::Client).tap do |client|
      allow(client).to receive(:paginate) do |endpoint, params: {}, &block|
        case endpoint
        when "customers"
          block.call({ "id" => "customer-1", "name" => "Avery Agent", "email" => "avery@example.test" })
        when "products"
          block.call({ "id" => "product-1", "title" => "Premium photos", "category_names" => [ "Photo" ],
                       "variants" => [ { "id" => "variant-1", "title" => "Up to 2,000 sqft", "price" => 54_900 } ] })
        when "listings"
          block.call({ "id" => "listing-1", "customer_id" => "customer-1", "address" => { "address_line_1" => "111 Oak Bay Ave", "city" => "Victoria", "province" => "BC" } })
        when "orders"
          block.call({ "id" => "order-1", "listing_id" => "listing-1", "customer_id" => "customer-1", "status" => "submitted", "total" => 54_900,
                       "items" => [ { "id" => "item-1", "title" => "Premium photos", "quantity" => 1, "price" => 54_900 } ] })
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
    # Aryeo quotes money in cents, so a `"price" => 54_900` variant is $549.00
    # and must be stored verbatim rather than scaled up by another 100.
    expect(Product.first.product_variants.first.price_cents).to eq(54_900)
    expect(Order.first.total_cents).to eq(54_900)
    expect(Order.first.order_items.first.unit_price_cents).to eq(54_900)
    expect(Listing.where(origin: "aryeo").pluck(:address_line_1)).to include("111 Oak Bay Ave")
    expect(Order.where(origin: "aryeo").count).to eq(1)
    expect(Order.first.order_items.count).to eq(1)
    expect(ExternalRecord.where(provider: "aryeo").count).to be >= 4
    expect(Listing.find(local_listing.id)).to be_present
  end

  it "keeps a limited development migration to the most recently changed listings" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate) do |endpoint, params: {}, &block|
      next unless endpoint == "listings"

      block.call({ "id" => "older-listing", "updated_at" => "2025-01-01T00:00:00Z", "address" => { "address_line_1" => "Older Street" } })
      block.call({ "id" => "newer-listing", "updated_at" => "2026-01-01T00:00:00Z", "address" => { "address_line_1" => "Newer Street" } })
    end

    described_class.new(run: import_run, client:, listing_limit: 1).call

    expect(Listing.where(origin: "aryeo").pluck(:address_line_1)).to contain_exactly("Newer Street")
  end

  it "can skip listing and media-bearing resources for a metadata-only import" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate) do |endpoint, params: {}, &block|
      block.call({ "id" => "product-1", "title" => "Premium photos" }) if endpoint == "products"
    end

    described_class.new(run: import_run, client:, skip_resources: [ :listings ]).call

    expect(client).not_to have_received(:paginate).with("listings")
    expect(connection.reload.endpoint_coverage).to include("listings" => include("status" => "skipped"))
    expect(Product.where(origin: "aryeo").count).to eq(1)
  end

  it "filters listings by their inclusive Aryeo update date range" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate) do |endpoint, params: {}, &block|
      next unless endpoint == "listings"

      block.call({ "id" => "old-listing", "updated_at" => "2025-12-31T23:59:59Z", "address" => { "address_line_1" => "Old Street" } })
      block.call({ "id" => "in-range-listing", "updated_at" => "2026-01-15T00:00:00Z", "address" => { "address_line_1" => "In Range Street" } })
      block.call({ "id" => "new-listing", "updated_at" => "2026-02-01T00:00:00Z", "address" => { "address_line_1" => "New Street" } })
      block.call({ "id" => "missing-date-listing", "address" => { "address_line_1" => "Missing Date Street" } })
    end

    run = import_run(resources: [ "listings" ])
    described_class.new(run:, client:, resources: [ "listings" ], import_start_date: "2026-01-01", import_end_date: "2026-01-31").call

    expect(run.reload.error_details).to be_empty
    expect(run.coverage.fetch("listings")).to include("count" => 2, "filtered_before_date" => 1,
                                                       "filtered_after_date" => 1, "date_unavailable" => 1)
    expect(Listing.where(origin: "aryeo").pluck(:address_line_1)).to contain_exactly("In Range Street", "Missing Date Street")
    expect(connection.reload.endpoint_coverage.fetch("listings")).to include("filtered_before_date" => 1,
                                                                                "filtered_after_date" => 1,
                                                                                "date_unavailable" => 1)
  end

  it "filters date-sensitive collections locally and expands listing media" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate)

    run = import_run(resources: %w[staff products listings orders appointments])
    described_class.new(run:, client:, resources: run.requested_resources, import_start_date: "2026-07-03").call

    expect(client).to have_received(:paginate).with("appointments")
    expect(client).to have_received(:paginate).with("orders")
    expect(client).to have_received(:paginate).with("listings", params: { "include" => described_class::LISTING_INCLUDE })
    expect(client).to have_received(:paginate).with("company-team-members")
    expect(client).to have_received(:paginate).with("products")
  end

  it "does not send remote date filters when both date bounds are present" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate)

    run = import_run(resources: %w[listings orders appointments])
    described_class.new(run:, client:, resources: run.requested_resources,
                        import_start_date: "2026-07-03", import_end_date: "2026-07-10").call

    expect(client).to have_received(:paginate).with("appointments")
    expect(client).to have_received(:paginate).with("orders")
    expect(client).to have_received(:paginate).with("listings", params: { "include" => described_class::LISTING_INCLUDE })
  end

  it "imports selected listing dependencies, nested order data, appointments, and expanded media" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate) do |endpoint, params: {}, &block|
      next unless endpoint == "listings"

      expect(params).to eq("include" => described_class::LISTING_INCLUDE)
      block.call(
        {
          "id" => "listing-1",
          "created_at" => "2026-07-04T12:00:00Z",
          "customer" => {
            "id" => "customer-1",
            "name" => "Avery Agent",
            "email" => "avery@example.test",
            "customer_team" => { "id" => "team-1", "name" => "Oak Bay Realty" }
          },
          "address" => { "address_line_1" => "111 Oak Bay Ave", "city" => "Victoria", "province" => "BC" },
          "images" => [ { "id" => "image-1", "filename" => "front.jpg", "original_url" => "https://media.example.test/front.jpg" } ],
          "orders" => [
            {
              "id" => "order-1",
              "status" => "submitted",
              "total" => 54_900,
              "items" => [ { "id" => "item-1", "title" => "Premium photos", "quantity" => 1, "price" => 54_900 } ],
              "appointments" => [ { "id" => "appointment-1", "start_at" => "2026-07-05T14:00:00Z", "status" => "confirmed" } ]
            }
          ]
        }
      )
    end

    run = import_run(resources: [ "listings" ])
    described_class.new(run:, client:, resources: [ "listings" ], import_start_date: "2026-07-03").call

    listing = organization.listings.find_by!(address_line_1: "111 Oak Bay Ave")
    expect(listing.client_account.email).to eq("avery@example.test")
    expect(listing.media_assets.find_by!(filename: "front.jpg").category).to eq("images")
    order = organization.orders.find_by!("metadata ->> 'aryeo_id' = ?", "order-1")
    expect(order.listing).to eq(listing)
    expect(order.order_items.pluck(:title)).to contain_exactly("Premium photos")
    expect(organization.appointments.find_by("notes LIKE ?", "%[aryeo:appointment-1]%")).to have_attributes(listing:, status: "confirmed")
    expect(organization.customer_teams.find_by!(name: "Oak Bay Realty").client_accounts).to contain_exactly(listing.client_account)
    expect(run.reload.coverage).to include(
      "clients" => include("status" => "imported_as_dependency"),
      "customer_teams" => include("status" => "imported_as_dependency"),
      "orders" => include("status" => "imported_as_dependency"),
      "appointments" => include("status" => "imported_as_dependency")
    )
  end

  it "filters orders and appointments locally while retaining records without an order date" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate) do |endpoint, params: {}, &block|
      case endpoint
      when "listings"
        block.call({ "id" => "listing-1", "created_at" => "2026-07-04T12:00:00Z", "address" => { "address_line_1" => "111 Oak Bay Ave" } })
      when "orders"
        block.call({ "id" => "order-in-range", "listing_id" => "listing-1", "created_at" => "2026-07-04T12:00:00Z", "total" => 10_000 })
        block.call({ "id" => "order-before-range", "listing_id" => "listing-1", "created_at" => "2026-07-02T12:00:00Z", "total" => 10_000 })
        block.call({ "id" => "order-without-date", "listing_id" => "listing-1", "total" => 10_000 })
      when "appointments"
        block.call({ "id" => "appointment-in-range", "listing_id" => "listing-1", "start_at" => "2026-07-05T12:00:00Z" })
        block.call({ "id" => "appointment-before-range", "listing_id" => "listing-1", "start_at" => "2026-07-02T12:00:00Z" })
        block.call({ "id" => "appointment-created-only", "listing_id" => "listing-1", "created_at" => "2026-07-06T12:00:00Z" })
      end
    end

    run = import_run(resources: %w[listings orders appointments])
    described_class.new(run:, client:, resources: run.requested_resources,
                        import_start_date: "2026-07-03", import_end_date: "2026-07-10").call

    expect(run.reload.coverage.fetch("orders")).to include("count" => 2, "filtered_before_date" => 1, "date_unavailable" => 1)
    expect(run.coverage.fetch("appointments")).to include("count" => 2, "filtered_before_date" => 1)
    expect(organization.orders.where(origin: :aryeo).count).to eq(2)
    expect(organization.appointments.where(origin: :aryeo).pluck(:starts_at)).to include(Time.zone.parse("2026-07-06T12:00:00Z"))
  end

  it "skips or overwrites records previously imported from the same Aryeo ID" do
    first_client = instance_double(Aryeo::Client)
    allow(first_client).to receive(:paginate) do |endpoint, params: {}, &block|
      block.call({ "id" => "customer-1", "name" => "Original name", "email" => "customer@example.test" }) if endpoint == "customers"
    end
    described_class.new(run: import_run(resources: [ "clients" ]), client: first_client, resources: [ "clients" ]).call

    changed_client = instance_double(Aryeo::Client)
    allow(changed_client).to receive(:paginate) do |endpoint, params: {}, &block|
      block.call({ "id" => "customer-1", "name" => "Changed in Aryeo", "email" => "customer@example.test" }) if endpoint == "customers"
    end

    described_class.new(run: import_run(resources: [ "clients" ]), client: changed_client, resources: [ "clients" ], conflict_resolution: "skip").call
    expect(ClientAccount.find_by!(email: "customer@example.test").name).to eq("Original name")

    described_class.new(run: import_run(resources: [ "clients" ], conflict_resolution: "overwrite"), client: changed_client, resources: [ "clients" ], conflict_resolution: "overwrite").call
    expect(ClientAccount.find_by!(email: "customer@example.test").name).to eq("Changed in Aryeo")
  end

  it "imports customer teams, preserves their source payload, and links imported clients" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate) do |endpoint, params: {}, &block|
      case endpoint
      when "customers"
        block.call({ "id" => "customer-1", "name" => "Avery Agent", "email" => "avery@example.test" })
      when "customer-teams"
        block.call({ "id" => "team-1", "name" => "Oak Bay Realty", "brokerage_website" => "https://oakbay.example.test",
                     "customer_ids" => [ "customer-1" ], "is_archived" => false, "internal_notes" => "Keep in Aryeo payload" })
      end
    end

    described_class.new(run: import_run(resources: %w[clients customer_teams]), client:, resources: %w[clients customer_teams]).call

    team = organization.customer_teams.find_by!(name: "Oak Bay Realty")
    expect(team).to be_aryeo
    expect(team.client_accounts.pluck(:email)).to contain_exactly("avery@example.test")
    expect(ExternalRecord.find_by!(resource_type: "customer_teams", external_id: "team-1").source_payload).to include("internal_notes" => "Keep in Aryeo payload")
  end
end
