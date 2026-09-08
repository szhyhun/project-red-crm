require "rails_helper"

RSpec.describe Orders::DeliverableMaterializer do
  let!(:organization) { Organization.create!(name: "Snapshot integrity agency", slug: "snapshot-integrity-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Snapshot client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "18 Snapshot Street") }
  let!(:photography) do
    organization.products.create!(slug: "snapshot-photography", title: "Property photography", kind: :service,
                                  description: "Photography as sold", deliverable_type: "photography", sla_days: 2)
  end
  let!(:video) do
    organization.products.create!(slug: "snapshot-video", title: "Property video", kind: :service,
                                  description: "Video as sold", deliverable_type: "video", sla_days: 3)
  end
  let!(:replacement_service) do
    organization.products.create!(slug: "snapshot-replacement", title: "Replacement service", kind: :service,
                                  description: "A later catalog service", deliverable_type: "files", sla_days: 9)
  end
  let!(:package) do
    organization.products.create!(slug: "snapshot-package", title: "Media package", kind: :package).tap do |product|
      product.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 50_000, sqft_min: 0, sqft_max: 1_000)
    end
  end
  let!(:component) { package.package_components.create!(organization:, service_product: photography, quantity: 2, position: 0) }
  let!(:variant) { package.product_variants.sole }

  def approved_package_order
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                  status: :approved, approved_at: Time.zone.parse("2026-09-08 09:00:00")).tap do |order|
      order.order_items.create!(product: package, product_variant: variant, title: "Media package - Up to 1,000 sqft",
                                quantity: 1, unit_price_cents: variant.price_cents, total_cents: variant.price_cents,
                                snapshot: OrderItem.catalog_snapshot(variant))
    end
  end

  it "materializes the sold component after the current package component was removed" do
    order = approved_package_order
    component.destroy!

    deliverable = described_class.new(order:).call.sole

    expect(deliverable).to have_attributes(
      product_component_id: nil,
      service_product: photography,
      title: "Property photography",
      description: "Photography as sold",
      deliverable_type: "photography",
      sla_days: 2
    )
    expect(deliverable.metadata).to include("component_quantity" => 2)
  end

  it "does not switch a sold component when the catalog row is repointed" do
    order = approved_package_order
    component.update!(service_product: replacement_service)

    deliverable = described_class.new(order:).call.sole

    expect(deliverable).to have_attributes(
      product_component_id: nil,
      service_product: photography,
      title: "Property photography",
      deliverable_type: "photography",
      sla_days: 2
    )
  end

  it "keeps the snapshot identity stable across retries" do
    order = approved_package_order
    first = described_class.new(order:).call
    component.update!(quantity: 3)

    second = described_class.new(order: order.reload).call

    expect(second.map(&:materialization_key)).to eq(first.map(&:materialization_key))
    expect(order.reload.order_deliverables.count).to eq(1)
  end

  it "still supports legacy package lines without a component snapshot" do
    order = approved_package_order
    order.order_items.sole.update!(snapshot: {})

    deliverable = described_class.new(order: order.reload).call.sole

    expect(deliverable).to have_attributes(product_component: component, service_product: photography)
    expect(deliverable.metadata).to include("component_quantity" => 2)
  end
end
