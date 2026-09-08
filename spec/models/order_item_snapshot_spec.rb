require "rails_helper"

RSpec.describe OrderItem, type: :model do
  let!(:organization) { Organization.create!(name: "Snapshot Agency", slug: "snapshot-agency") }
  let!(:service) do
    organization.products.create!(slug: "snapshot-service", title: "Property photography", kind: :service,
                                  deliverable_type: "photography")
  end

  it "captures price and square-foot scope independently of the mutable variant" do
    variant = service.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 29_900,
                                                sqft_min: 0, sqft_max: 1_000, quantity_label: "One property")

    snapshot = described_class.catalog_snapshot(variant)
    variant.update!(title: "New tier", price_cents: 39_900, sqft_min: 1_001, sqft_max: 2_000,
                    quantity_label: "Two properties")

    expect(snapshot).to include(
      product_title: "Property photography",
      variant_title: "Up to 1,000 sqft",
      price_cents: 29_900,
      sqft_min: 0,
      sqft_max: 1_000,
      quantity_label: "One property"
    )
  end

  it "records an explicit nil scope for a flat-rate service" do
    variant = service.product_variants.create!(title: "Flat rate", price_cents: 10_000)

    expect(described_class.catalog_snapshot(variant)).to include(
      sqft_min: nil,
      sqft_max: nil,
      quantity_label: nil
    )
  end

  it "captures package component service metadata" do
    package = organization.products.create!(slug: "snapshot-package", title: "Photo package", kind: :package)
    package.product_variants.create!(title: "Standard", price_cents: 50_000)
    component_service = organization.products.create!(
      slug: "snapshot-component-service",
      title: "Photography",
      kind: :service,
      description: "Original service description",
      deliverable_type: "photography",
      sla_days: 2
    )
    component = package.package_components.create!(organization:, service_product: component_service, position: 0)

    snapshot = described_class.catalog_snapshot(package.product_variants.sole)

    expect(snapshot[:components]).to include(
      hash_including(
        component_id: component.id,
        service_product_id: component_service.id,
        title: "Photography",
        description: "Original service description",
        deliverable_type: "photography",
        sla_days: 2
      )
    )
  end
end
