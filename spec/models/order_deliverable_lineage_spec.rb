require "rails_helper"

RSpec.describe OrderDeliverable, type: :model do
  let!(:organization) { Organization.create!(name: "Lineage Agency", slug: "lineage-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Lineage client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "1 Lineage Street") }
  let!(:service) do
    organization.products.create!(slug: "lineage-photo", title: "Property photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:other_service) do
    organization.products.create!(slug: "lineage-video", title: "Property video", kind: :service,
                                  deliverable_type: "video", sla_days: 3)
  end
  let!(:package) do
    organization.products.create!(slug: "lineage-package", title: "Photo package", kind: :package,
                                  deliverable_type: "other")
  end
  let!(:service_variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:other_variant) { other_service.product_variants.create!(title: "Standard", price_cents: 30_000) }
  let!(:package_variant) { package.product_variants.create!(title: "Standard", price_cents: 45_000) }
  let!(:component) { package.package_components.create!(organization:, service_product: service, quantity: 1, position: 0) }
  let!(:order) { Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later) }
  let!(:standalone_item) do
    order.order_items.create!(product: service, product_variant: service_variant, title: service.title, quantity: 1,
                              unit_price_cents: 20_000, total_cents: 20_000)
  end
  let!(:other_item) do
    order.order_items.create!(product: other_service, product_variant: other_variant, title: other_service.title,
                              quantity: 1, unit_price_cents: 30_000, total_cents: 30_000)
  end
  let!(:package_item) do
    order.order_items.create!(product: package, product_variant: package_variant, title: package.title, quantity: 1,
                              unit_price_cents: 45_000, total_cents: 45_000)
  end

  def build_deliverable(attributes = {})
    described_class.new({
      organization:, listing:, order:, order_item: standalone_item, service_product: service,
      title: service.title, deliverable_type: service.deliverable_type, sla_days: service.sla_days,
      materialization_key: "lineage-#{SecureRandom.uuid}"
    }.merge(attributes))
  end

  it "accepts a standalone deliverable only when its item purchased the same service" do
    expect(build_deliverable).to be_valid
    invalid = build_deliverable(order_item: other_item)

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include(
      "Order item must reference the standalone service product"
    )
  end

  it "accepts a package deliverable when its item purchased the containing package" do
    deliverable = build_deliverable(order_item: package_item, product_component: component)

    expect(deliverable).to be_valid
  end

  it "rejects a package deliverable attached to a standalone service item" do
    deliverable = build_deliverable(product_component: component)

    expect(deliverable).not_to be_valid
    expect(deliverable.errors.full_messages).to include("Order item must belong to the package product")
  end

  it "rejects a component whose service product does not match the deliverable" do
    mismatched_component = package.package_components.create!(organization:, service_product: other_service,
                                                              quantity: 1, position: 1)
    deliverable = build_deliverable(order_item: package_item, product_component: mismatched_component)

    expect(deliverable).not_to be_valid
    expect(deliverable.errors.full_messages).to include(
      "Product component must belong to the selected service and organization"
    )
  end

  it "shows only the current customer-visible final asset version" do
    original = build_asset(filename: "original.jpg", position: 0)
    replacement = build_asset(filename: "replacement.jpg", position: 1, version: 2)
    original.update!(superseded_by: replacement)
    hidden = build_asset(filename: "hidden.jpg", customer_visible: false)

    expect(deliverable_for_assets.customer_visible_assets).to eq([ replacement ])
    expect(deliverable_for_assets.customer_visible_assets).not_to include(original, hidden)
  end

  private

  def deliverable_for_assets
    @deliverable_for_assets ||= build_deliverable.tap(&:save!)
  end

  def build_asset(filename:, position: 0, version: 1, customer_visible: true)
    deliverable_for_assets.media_assets.create!(organization:, listing:, order:, order_item: standalone_item,
                                                 kind: :final, status: :ready, storage_key: "lineage/#{filename}",
                                                 filename:, content_type: "image/jpeg", byte_size: 5, position:, version:,
                                                 customer_visible:)
  end
end
