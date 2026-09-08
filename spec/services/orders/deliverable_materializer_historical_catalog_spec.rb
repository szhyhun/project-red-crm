require "rails_helper"

RSpec.describe Orders::DeliverableMaterializer do
  let!(:organization) { Organization.create!(name: "Historical catalog agency", slug: "historical-catalog-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Historical catalog client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "8 Historical Catalog Street") }
  let!(:photography) do
    organization.products.create!(slug: "historical-catalog-photography", title: "Property photography", kind: :service,
                                  deliverable_type: "photography", description: "Original description", sla_days: 2)
  end
  let!(:video) do
    organization.products.create!(slug: "historical-catalog-video", title: "Property video", kind: :service,
                                  deliverable_type: "video", description: "Video description", sla_days: 3)
  end
  let!(:package) do
    organization.products.create!(slug: "historical-catalog-package", title: "Media package", kind: :package).tap do |product|
      product.product_variants.create!(title: "Standard", price_cents: 50_000, sqft_min: 0, sqft_max: 1_000)
      product.package_components.create!(organization:, service_product: photography, position: 0)
      product.package_components.create!(organization:, service_product: video, position: 1)
    end
  end
  let!(:order) do
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                  status: :approved, approved_at: Time.current).tap do |record|
      variant = package.product_variants.sole
      record.order_items.create!(product: package, product_variant: variant, title: "Media package - Standard",
                                 quantity: 1, unit_price_cents: variant.price_cents, total_cents: variant.price_cents,
                                 snapshot: OrderItem.catalog_snapshot(variant))
    end
  end

  it "keeps existing deliverables stable when the catalog is changed after approval" do
    initial = described_class.new(order:).call
    component_ids = initial.map(&:product_component_id)

    package.package_components.find_by!(service_product: video).update!(quantity: 4)
    photography.update!(title: "Retitled photography", description: "New description", sla_days: 99)

    retry_result = described_class.new(order: order.reload).call

    expect(retry_result.map(&:id)).to eq(initial.map(&:id))
    expect(order.reload.order_deliverables.count).to eq(2)
    expect(order.order_deliverables.pluck(:product_component_id)).to contain_exactly(*component_ids)
    expect(order.order_deliverables.find_by!(service_product: photography)).to have_attributes(
      title: "Property photography", description: "Original description", sla_days: 2
    )
  end

  it "does not allow a component used by a historical deliverable to be deleted" do
    described_class.new(order:).call
    component = package.package_components.find_by!(service_product: video)

    expect { component.destroy! }.to raise_error(ActiveRecord::InvalidForeignKey)
    expect(OrderDeliverable.where(product_component_id: component.id)).to exist
  end

  it "materializes a package component once even when the order quantity is greater than one" do
    order.order_items.sole.update!(quantity: 2, total_cents: 100_000)

    deliverables = described_class.new(order: order.reload).call

    expect(deliverables.size).to eq(2)
    expect(deliverables.map { |deliverable| deliverable.metadata.fetch("quantity") }).to all(eq(2))
    expect(deliverables.map(&:product_component_id)).to contain_exactly(*package.package_components.ids)
  end

  it "does not let a cancelled package line recreate delivery work" do
    order.order_items.sole.update!(cancelled_at: Time.current)

    expect { described_class.new(order: order.reload).call }.not_to change(OrderDeliverable, :count)
  end

  it "uses the product metadata sold with the order when approval happens later" do
    variant = package.product_variants.sole
    sold_order = Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later)
    sold_order.order_items.create!(product: package, product_variant: variant,
                                   title: "Media package - Standard", quantity: 1,
                                   unit_price_cents: variant.price_cents, total_cents: variant.price_cents,
                                   snapshot: OrderItem.catalog_snapshot(variant))
    sold_order.update!(status: :approved, approved_at: Time.zone.parse("2026-09-07 09:00"))

    photography.update!(
      title: "Renamed photography",
      description: "Changed after checkout",
      deliverable_type: :files,
      sla_days: 10
    )

    deliverable = described_class.new(order: sold_order.reload).call.find_by(service_product_id: photography.id)

    expect(deliverable).to have_attributes(
      title: "Property photography",
      description: "Original description",
      deliverable_type: "photography",
      sla_days: 2
    )
  end
end
