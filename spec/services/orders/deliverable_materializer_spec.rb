require "rails_helper"

RSpec.describe Orders::DeliverableMaterializer do
  let!(:organization) { Organization.create!(name: "Materializer Agency", slug: "materializer-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Materializer client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "10 Materializer Street") }
  let!(:photo_service) do
    organization.products.create!(slug: "materializer-photo", title: "Property photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:video_service) do
    organization.products.create!(slug: "materializer-video", title: "Property video", kind: :service,
                                  deliverable_type: "video", sla_days: 3)
  end
  let!(:package) do
    organization.products.create!(slug: "materializer-package", title: "Media package", kind: :package).tap do |product|
      product.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 50_000, sqft_min: 0, sqft_max: 1_000)
      product.package_components.create!(organization:, service_product: photo_service, quantity: 1, position: 0)
      product.package_components.create!(organization:, service_product: video_service, quantity: 1, position: 1)
    end
  end

  def build_order(items:)
    order = Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                          status: :approved, approved_at: Time.zone.parse("2026-09-07 09:00:00"))
    items.each do |attributes|
      order.order_items.create!(attributes.merge(quantity: 1, unit_price_cents: attributes.fetch(:unit_price_cents),
                                                 total_cents: attributes.fetch(:unit_price_cents)))
    end
    order
  end

  it "creates one deliverable per package service and copies the selected package scope" do
    order = build_order(items: [ { product: package, product_variant: package.product_variants.first,
                                   title: "Media package", unit_price_cents: 50_000 } ])

    deliverables = described_class.new(order:).call

    expect(deliverables.map(&:service_product_id)).to eq([ photo_service.id, video_service.id ])
    expect(deliverables.map(&:scope_label)).to eq([ "0–1,000 sqft", "0–1,000 sqft" ])
    expect(deliverables.map(&:product_component_id)).to eq(package.package_components.ordered.ids)
    expect(deliverables.map(&:position)).to eq([ 0, 1 ])
  end

  it "creates a standalone deliverable from a service order item" do
    variant = photo_service.product_variants.create!(title: "Standard", price_cents: 30_000,
                                                      sqft_min: 1_001, sqft_max: 2_000)
    order = build_order(items: [ { product: photo_service, product_variant: variant,
                                   title: "Property photography", unit_price_cents: 30_000 } ])

    deliverable = described_class.new(order:).call.sole

    expect(deliverable).to have_attributes(service_product: photo_service, product_component: nil,
                                           scope_sqft_min: 1_001, scope_sqft_max: 2_000,
                                           scope_label: "1,001–2,000 sqft", position: 0)
  end

  it "keeps an open-ended sold tier and gives the deliverable a readable scope" do
    variant = photo_service.product_variants.create!(title: "2,001+ sqft", price_cents: 45_000, sqft_min: 2_001)
    order = build_order(items: [ { product: photo_service, product_variant: variant,
                                   title: "Property photography", unit_price_cents: 45_000 } ])

    deliverable = described_class.new(order:).call.sole

    expect(deliverable).to have_attributes(scope_sqft_min: 2_001, scope_sqft_max: nil, scope_label: "2,001+ sqft")
  end

  it "uses the sold variant scope when the catalog changes before approval" do
    variant = photo_service.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 30_000,
                                                      sqft_min: 0, sqft_max: 1_000)
    order = Orders::Creator.new(
      organization:,
      attributes: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: variant.id, quantity: 1 } ]
      }
    ).create!
    variant.update!(title: "Up to 3,000 sqft", sqft_min: 1_001, sqft_max: 3_000)
    order.update!(status: :approved, approved_at: Time.zone.parse("2026-09-07 09:00:00"))

    deliverable = described_class.new(order:).call.sole

    expect(deliverable).to have_attributes(
      scope_sqft_min: 0,
      scope_sqft_max: 1_000,
      scope_label: "0–1,000 sqft"
    )
  end

  it "does not materialize cancelled items" do
    order = build_order(items: [ { product: photo_service, title: "Cancelled photography", unit_price_cents: 30_000 } ])
    order.order_items.sole.update!(cancelled_at: Time.current)

    expect(described_class.new(order:).call).to be_empty
  end

  it "is idempotent and does not rewrite a historical deliverable after catalog changes" do
    variant = photo_service.product_variants.create!(title: "Standard", price_cents: 30_000)
    order = build_order(items: [ { product: photo_service, product_variant: variant,
                                   title: "Property photography", unit_price_cents: 30_000 } ])
    materializer = described_class.new(order:)
    first = materializer.call.sole
    first.update!(title: "Old title")
    photo_service.update!(title: "New catalog title", description: "New catalog description", sla_days: 10)
    variant.update!(title: "New catalog tier", price_cents: 40_000)

    second = materializer.call.sole

    expect(second.id).to eq(first.id)
    expect(second.reload).to have_attributes(title: "Old title", description: nil, sla_days: 2, scope_label: "Standard")
    expect(order.order_deliverables.count).to eq(1)
  end

  it "uses business days when calculating a target date" do
    order = build_order(items: [ { product: photo_service, title: "Property photography", unit_price_cents: 30_000 } ])

    deliverable = described_class.new(order:).call.sole

    # September 7, 2026 is a Monday; two business days later is Wednesday.
    expect(deliverable.target_on).to eq(Date.new(2026, 9, 9))
  end

  it "keeps an order without a listing usable for internal work" do
    order = Order.create!(organization:, client_account:, payment_mode: :pay_later, status: :approved,
                          approved_at: Time.zone.parse("2026-09-07 09:00:00"))
    order.order_items.create!(product: video_service, title: "Video", quantity: 1, unit_price_cents: 20_000,
                              total_cents: 20_000)

    deliverable = described_class.new(order:).call.sole

    expect(deliverable.listing).to be_nil
    expect(deliverable.order_id).to eq(order.id)
  end
end
