require "rails_helper"

RSpec.describe Orders::DeliverableMaterializer do
  let!(:organization) { Organization.create!(name: "Mixed purchase agency", slug: "mixed-purchase-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Mixed purchase client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "50 Mixed Purchase Street") }
  let!(:photography) do
    organization.products.create!(slug: "mixed-purchase-photography", title: "Standard property photography",
                                  kind: :service, deliverable_type: "photography", sla_days: 2)
  end
  let!(:video) do
    organization.products.create!(slug: "mixed-purchase-video", title: "Standard property video",
                                  kind: :service, deliverable_type: "video", sla_days: 3)
  end
  let!(:package) do
    organization.products.create!(slug: "mixed-purchase-package", title: "Complete media package", kind: :package,
                                  deliverable_type: "other").tap do |product|
      product.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 49_000, sqft_min: 0, sqft_max: 1_000)
      product.package_components.create!(organization:, service_product: photography, quantity: 1, position: 0)
      product.package_components.create!(organization:, service_product: video, quantity: 1, position: 1)
    end
  end
  let!(:package_variant) { package.product_variants.sole }
  let!(:standalone_variant) do
    photography.product_variants.create!(title: "1,001–2,000 sqft", price_cents: 34_000,
                                         sqft_min: 1_001, sqft_max: 2_000)
  end

  def approved_order
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                  status: :approved, approved_at: Time.zone.parse("2026-09-08 09:00:00"))
  end

  def add_item(order, product:, variant:, title: product.title, price_cents: variant.price_cents, quantity: 1)
    order.order_items.create!(product:, product_variant: variant, title:, quantity:, unit_price_cents: price_cents,
                              total_cents: price_cents * quantity, snapshot: OrderItem.catalog_snapshot(variant, price_cents:))
  end

  it "materializes package services and standalone purchases from one order" do
    order = approved_order
    add_item(order, product: package, variant: package_variant, title: "Complete media package")
    add_item(order, product: photography, variant: standalone_variant, title: "Photography add-on")

    deliverables = described_class.new(order:).call

    expect(order.order_items.count).to eq(2)
    expect(deliverables.map(&:service_product_id)).to eq([ photography.id, video.id, photography.id ])
    expect(deliverables.first(2).map(&:product_component_id)).to eq(package.package_components.ordered.ids)
    expect(deliverables.last.product_component).to be_nil
    expect(deliverables.first(2).map(&:scope_label)).to all(eq("0–1,000 sqft"))
    expect(deliverables.last).to have_attributes(scope_sqft_min: 1_001, scope_sqft_max: 2_000,
                                                  scope_label: "1,001–2,000 sqft")
  end

  it "does not create invoice-like price records for included services" do
    order = approved_order
    add_item(order, product: package, variant: package_variant, title: "Complete media package")

    deliverables = described_class.new(order:).call

    expect(deliverables).to all(satisfy { |deliverable| deliverable.product_component.present? })
    expect(deliverables.map { |deliverable| deliverable.metadata["price_cents"] }).to all(be_nil)
    expect(order.order_items.map(&:total_cents)).to eq([ 49_000 ])
  end

  it "skips a cancelled standalone line while retaining the package delivery work" do
    order = approved_order
    add_item(order, product: package, variant: package_variant, title: "Complete media package")
    standalone = add_item(order, product: photography, variant: standalone_variant, title: "Cancelled add-on")
    standalone.update!(cancelled_at: Time.current)

    deliverables = described_class.new(order:).call

    expect(deliverables.map(&:service_product_id)).to eq([ photography.id, video.id ])
    expect(deliverables.map(&:product_component_id)).to eq(package.package_components.ordered.ids)
    expect(deliverables.map { |deliverable| deliverable.materialization_key }).to all(start_with("order:"))
  end
end
