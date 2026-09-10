require "rails_helper"

RSpec.describe Aryeo::ImportedDeliveryMaterializer do
  let!(:organization) { Organization.create!(name: "Imported delivery agency", slug: "imported-delivery-agency") }
  let!(:connection) do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
  end
  let!(:run) do
    connection.integration_import_runs.create!(organization:, provider: :aryeo,
                                                requested_resources: %w[products listings orders])
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Imported customer", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "Imported Media Street") }
  let!(:products) do
    [
      [ "Imported photography", "imported-photo", "photography" ],
      [ "Imported video", "imported-video", "video" ],
      [ "Imported floor plan", "imported-floor-plan", "floor_plan" ],
      [ "Imported files", "imported-files", "files" ],
      [ "Imported tour", "imported-tour", "tour" ]
    ].map do |title, external_id, deliverable_type|
      organization.products.create!(title:, slug: external_id, external_source: "aryeo", external_id:,
                                    kind: :service, deliverable_type:, sla_days: 2).tap do |product|
        product.product_variants.create!(title: "Standard", price_cents: 10_000, external_id: "#{external_id}-variant")
      end
    end
  end
  let!(:order) do
    Order.create!(organization:, client_account:, listing:, status: :submitted, fulfillment_status: :unfulfilled,
                  metadata: { "aryeo_id" => "order-1" }).tap do |record|
      products.each_with_index do |product, index|
        variant = product.product_variants.sole
        record.order_items.create!(product:, product_variant: variant, title: product.title, quantity: 1,
                                   unit_price_cents: variant.price_cents, total_cents: variant.price_cents,
                                   options: { "aryeo_id" => "item-#{index + 1}" })
      end
    end
  end
  let!(:order_record) do
    ExternalRecord.create!(organization:, integration_connection: connection, integration_import_run: run,
                           provider: :aryeo, resource_type: "orders", external_id: "order-1", record: order,
                           source_payload: { "id" => "order-1", "status" => "submitted",
                                             "updated_at" => "2026-09-10T12:00:00Z" })
  end

  it "materializes imported services and links every media category without duplicating on retry" do
    media = [
      [ "photo-1", "images", "item-1", "front.jpg", "image/jpeg" ],
      [ "video-1", "videos", "item-2", "walkthrough.mp4", "video/mp4" ],
      [ "floor-plan-1", "floor_plans", "item-3", "main-floor.pdf", "application/pdf" ],
      [ "file-1", "files", "item-4", "brochure.pdf", "application/pdf" ]
    ].map do |external_id, category, item_external_id, filename, content_type|
      asset = listing.media_assets.create!(organization:, kind: :final, status: :pending,
                                           storage_key: "aryeo/#{external_id}", filename:, content_type:,
                                           category:, customer_visible: true, origin: :aryeo)
      ExternalRecord.create!(organization:, integration_connection: connection, integration_import_run: run,
                             provider: :aryeo, resource_type: "media_assets", external_id:, record: asset,
                             source_payload: { "id" => external_id, "order_id" => "order-1",
                                               "order_item_id" => item_external_id })
      asset
    end

    result = described_class.new(run:).call

    expect(result.fetch(:deliverables).pluck(:deliverable_type)).to contain_exactly(
      "photography", "video", "floor_plan", "files", "tour"
    )
    expect(result.fetch(:linked_media_assets)).to contain_exactly(*media)
    expect(order.reload.order_deliverables.count).to eq(5)
    expect(order.order_deliverables.where.not(deliverable_type: "tour"))
      .to all(have_attributes(status: "delivered", delivered_at: be_present))
    expect(order.order_deliverables.find_by!(deliverable_type: "tour"))
      .to have_attributes(status: "not_started", delivered_at: nil)
    expect(media.map { |asset| asset.reload.order_deliverable.deliverable_type }).to contain_exactly(
      "photography", "video", "floor_plan", "files"
    )

    expect {
      described_class.new(run:).call
    }.not_to change(OrderDeliverable, :count)
  end

  it "does not link media from another organization" do
    other_organization = Organization.create!(name: "Other imported agency", slug: "other-imported-agency")
    other_client = ClientAccount.create!(organization: other_organization, name: "Other customer", kind: :agent)
    other_listing = Listing.create!(organization: other_organization, client_account: other_client,
                                    address_line_1: "Other Imported Street")
    asset = other_listing.media_assets.create!(organization: other_organization, kind: :final, status: :pending,
                                               storage_key: "other-aryeo/photo", filename: "photo.jpg",
                                               content_type: "image/jpeg", category: "images", origin: :aryeo)
    ExternalRecord.create!(organization: other_organization, integration_connection: connection,
                           integration_import_run: run, provider: :aryeo, resource_type: "media_assets",
                           external_id: "foreign-photo", record: asset,
                           source_payload: { "id" => "foreign-photo", "order_id" => "order-1" })

    described_class.new(run:).call

    expect(asset.reload.order_deliverable).to be_nil
  end
end
