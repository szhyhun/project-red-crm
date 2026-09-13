require "rails_helper"

RSpec.describe Integrations::Aryeo::Organizers::ImportOrganizer do
  let!(:organization) { Organization.create!(name: "Import Agency", slug: "import-agency") }
  let!(:connection) { IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected) }

  def import_run(resources: Aryeo::ImportSession::RESOURCE_KEYS, conflict_resolution: "skip")
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
                       "items" => [ { "id" => "item-1", "product_id" => "product-1", "product_variant_id" => "variant-1",
                                     "title" => "Premium photos", "quantity" => 1, "price" => 54_900 } ] })
        end
      end
    end
  end

  it "upserts mapped records, preserves Aryeo provenance, and keeps unrelated local records" do
    local_client = ClientAccount.create!(organization:, name: "Local agent")
    local_listing = Listing.create!(organization:, client_account: local_client, address_line_1: "Local Street")

    described_class.call(run: import_run, client: client_with_catalog)
    described_class.call(run: import_run, client: client_with_catalog)

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
    expect(Order.first.order_deliverables).to contain_exactly(
      have_attributes(deliverable_type: "photography", status: "not_started")
    )
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

    described_class.call(run: import_run, client:, listing_limit: 1)

    expect(Listing.where(origin: "aryeo").pluck(:address_line_1)).to contain_exactly("Newer Street")
  end

  it "can skip listing and media-bearing resources for a metadata-only import" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate) do |endpoint, params: {}, &block|
      block.call({ "id" => "product-1", "title" => "Premium photos" }) if endpoint == "products"
    end

    described_class.call(run: import_run, client:, skip_resources: [ :listings ])

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
    described_class.call(run:, client:, resources: [ "listings" ], import_start_date: "2026-01-01", import_end_date: "2026-01-31")

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
    described_class.call(run:, client:, resources: run.requested_resources, import_start_date: "2026-07-03")

    expect(client).to have_received(:paginate).with("appointments")
    expect(client).to have_received(:paginate).with("orders", params: { "include" => Aryeo::ImportSession::ORDER_INCLUDE })
    expect(client).to have_received(:paginate).with("listings", params: { "include" => Aryeo::ImportSession::LISTING_INCLUDE })
    expect(client).to have_received(:paginate).with("company-team-members")
    expect(client).to have_received(:paginate).with("products")
  end

  it "does not send remote date filters when both date bounds are present" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate)

    run = import_run(resources: %w[listings orders appointments])
    described_class.call(run:, client:, resources: run.requested_resources,
                        import_start_date: "2026-07-03", import_end_date: "2026-07-10")

    expect(client).to have_received(:paginate).with("appointments")
    expect(client).to have_received(:paginate).with("orders", params: { "include" => Aryeo::ImportSession::ORDER_INCLUDE })
    expect(client).to have_received(:paginate).with("listings", params: { "include" => Aryeo::ImportSession::LISTING_INCLUDE })
  end

  it "imports selected listing dependencies, nested order data, appointments, and expanded media" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate) do |endpoint, params: {}, &block|
      next unless endpoint == "listings"

      expect(params).to eq("include" => Aryeo::ImportSession::LISTING_INCLUDE)
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
          "images" => [
            { "id" => "image-1", "filename" => "front.jpg", "original_url" => "https://media.example.test/front.jpg", "index" => 2 },
            { "id" => "image-2", "filename" => "backyard", "large_url" => "https://media.example.test/backyard.jpg", "index" => 1 }
          ],
          "videos" => [
            { "id" => "video-1", "title" => "Property video", "duration" => 92,
              "download_url" => "https://videos.aryeo.com/listings/listing-1/video-1.mp4" }
          ],
          "floor_plans" => [
            { "id" => "floor-plan-1", "title" => "Main floor", "large_url" => "https://media.example.test/main-floor.png", "index" => 3 }
          ],
          "files" => [
            { "uuid" => "file-1", "filename" => "property-brochure", "file_type" => "pdf",
              "url" => "https://cdn.aryeo.com/listings/listing-1/brochure.pdf" },
            { "uuid" => "file-2", "filename" => "site-photo", "file_type" => "jpg",
              "url" => "https://cdn.aryeo.com/listings/listing-1/site-photo.jpg" }
          ],
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
    expect {
      described_class.call(run:, client:, resources: [ "listings" ], import_start_date: "2026-07-03")
    }.to have_enqueued_job(AryeoMediaCopyJob).exactly(6).times

    listing = organization.listings.find_by!(address_line_1: "111 Oak Bay Ave")
    expect(listing.client_account.email).to eq("avery@example.test")
    expect(listing.media_assets.pluck(:category, :filename, :content_type, :position)).to contain_exactly(
      [ "images", "front.jpg", "image/jpeg", 2 ],
      [ "images", "backyard.jpg", "image/jpeg", 1 ],
      [ "videos", "Property video.mp4", "video/mp4", 0 ],
      [ "floor_plans", "Main floor.png", "image/png", 3 ],
      [ "files", "property-brochure.pdf", "application/pdf", 0 ],
      [ "images", "site-photo.jpg", "image/jpeg", 0 ]
    )
    expect(listing.media_assets.where(status: :pending).count).to eq(6)
    expect(connection.external_records.where(resource_type: "media_assets", sync_status: :pending_media_copy).count).to eq(6)
    expect(run.reload.coverage.fetch("listings")).to include("media_assets" => { "queued" => 6 })
    order = organization.orders.find_by!("metadata ->> 'aryeo_id' = ?", "order-1")
    expect(order.listing).to eq(listing)
    expect(order.order_items.pluck(:title)).to contain_exactly("Premium photos")
    expect(organization.appointments.find_by("notes LIKE ?", "%[aryeo:appointment-1]%")).to have_attributes(listing:, status: "confirmed")
    team = organization.client_accounts.find_by!(name: "Oak Bay Realty")
    expect(team).to be_team
    # The person joins the team with an invitation nobody has sent yet.
    expect(team.client_memberships.sole).to have_attributes(status: "invited", role: "member")
    expect(team.client_memberships.sole.user.email).to eq("avery@example.test")
    expect(run.reload.coverage).to include(
      "clients" => include("status" => "imported_as_dependency"),
      "customer_teams" => include("status" => "imported_as_dependency"),
      "orders" => include("status" => "imported_as_dependency"),
      "appointments" => include("status" => "imported_as_dependency")
    )
  end

  it "records a listing media failure when Aryeo omits a downloadable URL" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate) do |endpoint, &block|
      next unless endpoint == "listings"

      block.call(
        "id" => "listing-without-video-download",
        "address" => { "address_line_1" => "Missing Video Download Street" },
        "videos" => [ { "id" => "video-without-download", "title" => "Hosted video", "playback_url" => "https://player.example.test/video" } ]
      )
    end

    run = import_run(resources: [ "listings" ])
    described_class.call(run:, client:, resources: [ "listings" ])

    asset = organization.media_assets.find_by!(filename: "Hosted video")
    expect(asset).to have_attributes(status: "failed", content_type: "video/mp4")
    expect(connection.external_records.find_by!(resource_type: "media_assets", external_id: "video-without-download")).to be_failed
    expect(run.reload).to be_completed_with_errors
    expect(run.coverage.fetch("listings")).to include("media_assets" => { "failed" => 1 })
    expect(run.error_details).to include(/video-without-download.*no downloadable URL/)
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
    described_class.call(run:, client:, resources: run.requested_resources,
                        import_start_date: "2026-07-03", import_end_date: "2026-07-10")

    expect(run.reload.coverage.fetch("orders")).to include("count" => 2, "filtered_before_date" => 1, "date_unavailable" => 1)
    expect(run.coverage.fetch("appointments")).to include("count" => 2, "filtered_before_date" => 1)
    expect(organization.orders.where(origin: :aryeo).count).to eq(2)
    expect(organization.appointments.where(origin: :aryeo).pluck(:starts_at)).to include(Time.zone.parse("2026-07-06T12:00:00Z"))
  end

  it "normalizes Aryeo catalog and order-item relationships from expanded API records" do
    client = instance_double(Aryeo::Client)
    photo_variant = {
      "id" => "photo-variant-1", "title" => "0–1,000 sqft", "price_amount" => 29_900,
      "duration" => 120, "subtitle" => "0–1,000 sqft"
    }
    photo_product = {
      "id" => "photo-product-1", "type" => "MAIN", "title" => "Standard Property Photography",
      "description" => "Professional interior and exterior photography.", "categories" => [ { "name" => "Photography" } ],
      "sla_days" => 2, "variants" => [ photo_variant ]
    }
    allow(client).to receive(:paginate) do |endpoint, params: {}, &block|
      case endpoint
      when "customers"
        block.call({ "id" => "customer-1", "first_name" => "Avery", "last_name" => "Agent", "email" => "avery@example.test" })
      when "products"
        block.call(photo_product)
      when "listings"
        block.call({ "id" => "listing-1", "customer_id" => "customer-1",
                     "address" => { "address_line_1" => "111 Oak Bay Ave", "city" => "Victoria", "province" => "BC" } })
      when "orders"
        block.call({
          "id" => "order-1", "listing_id" => "listing-1", "customer_id" => "customer-1", "status" => "submitted",
          "total_amount" => 29_900, "items" => [ {
            "id" => "order-item-1", "product_variant_id" => "photo-variant-1", "quantity" => 1,
            "title" => "Standard Property Photography — 0–1,000 sqft", "unit_price_amount" => 29_900,
            "total_amount" => 29_900, "product" => photo_product, "product_variant" => photo_variant
          } ]
        })
      end
    end

    run = import_run(resources: %w[clients products listings orders])
    described_class.call(run:, client:, resources: run.requested_resources)

    product = organization.products.find_by!(external_id: "photo-product-1")
    variant = product.product_variants.find_by!(external_id: "photo-variant-1")
    expect(product).to have_attributes(kind: "service", deliverable_type: "photography", sla_days: 2)
    expect(variant).to have_attributes(price_cents: 29_900, sqft_min: 0, sqft_max: 1_000, duration_minutes: 120)

    item = organization.orders.find_by!("metadata ->> 'aryeo_id' = ?", "order-1").order_items.sole
    expect(item).to have_attributes(product:, product_variant: variant, unit_price_cents: 29_900, total_cents: 29_900)
    expect(item.snapshot).to include("product_title" => "Standard Property Photography", "sqft_max" => 1_000)
    expect(item.order).to have_attributes(total_cents: 29_900)
    expect(item.order.client_account.name).to eq("Avery Agent")
  end

  it "imports Aryeo MAIN and ADDON products without inventing ProjectRed packages" do
    client = instance_double(Aryeo::Client)
    photo_product = {
      "id" => "photo-product-1", "type" => "MAIN", "title" => "Standard Property Photography",
      "categories" => [ "Photography" ], "variants" => [ { "id" => "photo-variant-1", "title" => "Up to 1,000 sqft", "price_amount" => 29_900 } ]
    }
    video_product = {
      "id" => "video-product-1", "type" => "MAIN", "title" => "Standard Video", "categories" => [ "Video" ],
      "variants" => [ { "id" => "video-variant-1", "title" => "Standard", "price_amount" => 19_900 } ]
    }
    package_titled_product = {
      "id" => "package-product-1", "type" => "MAIN", "title" => "Photo + Video Package",
      "variants" => [ { "id" => "package-variant-1", "title" => "Photo + Video — Up to 1,000 sqft", "price_amount" => 44_900 } ],
      "components" => [
        { "product" => photo_product, "quantity" => 1 },
        { "product" => video_product, "quantity" => 1 }
      ]
    }
    addon_product = {
      "id" => "addon-product-1", "type" => "ADDON", "title" => "Rush delivery add-on",
      "variants" => [ { "id" => "addon-variant-1", "title" => "Rush", "price_amount" => 9_900 } ]
    }
    allow(client).to receive(:paginate) do |endpoint, params: {}, &block|
      case endpoint
      when "products"
        block.call(package_titled_product)
        block.call(addon_product)
      when "orders"
        block.call({
          "id" => "package-order-1", "status" => "submitted", "total" => 44_900,
          "items" => [ { "id" => "package-item-1", "product_variant_id" => "package-variant-1",
                         "product" => package_titled_product,
                         "product_variant" => package_titled_product.fetch("variants").first,
                         "unit_price_amount" => 44_900, "total_amount" => 44_900 } ]
        })
      end
    end

    run = import_run(resources: %w[products orders])
    described_class.call(run:, client:, resources: run.requested_resources)

    package_titled_product = organization.products.find_by!(external_id: "package-product-1")
    expect(package_titled_product).to be_service
    expect(package_titled_product.package_components).to be_empty
    expect(organization.products.find_by!(external_id: "addon-product-1")).to be_addon

    item = organization.orders.find_by!("metadata ->> 'aryeo_id' = ?", "package-order-1").order_items.sole
    expect(item.product).to eq(package_titled_product)
    expect(item.snapshot).not_to have_key("components")
  end

  it "imports a nested customer as an order dependency when only orders are selected" do
    client = instance_double(Aryeo::Client)
    allow(client).to receive(:paginate) do |endpoint, params: {}, &block|
      block.call({
        "id" => "order-1", "status" => "submitted", "total" => 10_000,
        "customer" => { "id" => "customer-1", "name" => "Nested Customer", "email" => "nested@example.test" },
        "items" => []
      }) if endpoint == "orders"
    end

    run = import_run(resources: [ "orders" ])
    described_class.call(run:, client:, resources: [ "orders" ])

    expect(organization.client_accounts.find_by!(email: "nested@example.test")).to have_attributes(origin: "aryeo")
    expect(run.reload.coverage.fetch("clients")).to include("status" => "imported_as_dependency", "count" => 1)
  end

  it "skips or overwrites records previously imported from the same Aryeo ID" do
    first_client = instance_double(Aryeo::Client)
    allow(first_client).to receive(:paginate) do |endpoint, params: {}, &block|
      block.call({ "id" => "customer-1", "name" => "Original name", "email" => "customer@example.test" }) if endpoint == "customers"
    end
    described_class.call(run: import_run(resources: [ "clients" ]), client: first_client, resources: [ "clients" ])

    changed_client = instance_double(Aryeo::Client)
    allow(changed_client).to receive(:paginate) do |endpoint, params: {}, &block|
      block.call({ "id" => "customer-1", "name" => "Changed in Aryeo", "email" => "customer@example.test" }) if endpoint == "customers"
    end

    described_class.call(run: import_run(resources: [ "clients" ]), client: changed_client, resources: [ "clients" ], conflict_resolution: "skip")
    expect(ClientAccount.find_by!(email: "customer@example.test").name).to eq("Original name")

    described_class.call(run: import_run(resources: [ "clients" ], conflict_resolution: "overwrite"), client: changed_client, resources: [ "clients" ], conflict_resolution: "overwrite")
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
                     "customer_ids" => [ "customer-1" ], "is_archived" => false, "internal_notes" => "Keep in Aryeo payload",
                     "customer_team_memberships" => [
                       { "role" => "ADMIN", "status" => "ACTIVE",
                         "customer_user" => { "id" => "customer-2", "email" => "tess@example.test", "first_name" => "Tess", "last_name" => "Admin" } },
                       { "role" => "MEMBER", "status" => "REVOKED",
                         "customer_user" => { "id" => "customer-3", "email" => "gone@example.test", "name" => "Gone Member" } }
                     ] })
      end
    end

    described_class.call(run: import_run(resources: %w[clients customer_teams]), client:, resources: %w[clients customer_teams])

    team = organization.client_accounts.find_by!(name: "Oak Bay Realty")
    expect(team).to have_attributes(kind: "team", origin: "aryeo", internal_note: "Keep in Aryeo payload",
                                    brokerage_website: "https://oakbay.example.test")
    expect(team.client_memberships.includes(:user).map { |membership| [ membership.user.email, membership.role, membership.status ] })
      .to contain_exactly([ "tess@example.test", "admin", "invited" ], [ "gone@example.test", "member", "revoked" ])
    # A person with no email cannot be invited, so only their own account arrives.
    expect(organization.client_accounts.find_by!(email: "avery@example.test")).to be_present
    record = ExternalRecord.find_by!(resource_type: "customer_teams", external_id: "team-1")
    expect(record.record).to eq(team)
    expect(record.source_payload).to include("internal_notes" => "Keep in Aryeo payload")
  end
end
