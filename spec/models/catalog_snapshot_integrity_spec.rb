require "rails_helper"

RSpec.describe "Catalog snapshot integrity", type: :model do
  let!(:organization) { Organization.create!(name: "Snapshot integrity agency", slug: "snapshot-integrity-agency") }
  let!(:service) do
    organization.products.create!(slug: "snapshot-integrity-service", title: "Property photography", kind: :service,
                                  description: "Original description", deliverable_type: "photography", sla_days: 2)
  end
  let!(:package) do
    organization.products.create!(slug: "snapshot-integrity-package", title: "Photo package", kind: :package,
                                  description: "Original package", deliverable_type: "other", sla_days: 1)
  end

  it "snapshots package component identity and service metadata instead of only live product ids" do
    component = package.package_components.create!(organization:, service_product: service, quantity: 2, position: 0)
    variant = package.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 50_000,
                                               sqft_min: 0, sqft_max: 1_000)

    snapshot = OrderItem.catalog_snapshot(variant)

    expect(snapshot).to include(
      product_title: "Photo package",
      variant_title: "Up to 1,000 sqft",
      price_cents: 50_000,
      sqft_min: 0,
      sqft_max: 1_000
    )
    expect(snapshot.fetch(:components)).to contain_exactly(
      hash_including(
        component_id: component.id,
        service_product_id: service.id,
        title: "Property photography",
        description: "Original description",
        deliverable_type: "photography",
        sla_days: 2,
        quantity: 2
      )
    )
  end

  it "keeps the sold package snapshot unchanged when the catalog is edited" do
    component = package.package_components.create!(organization:, service_product: service, quantity: 1, position: 0)
    variant = package.product_variants.create!(title: "Standard", price_cents: 40_000)
    item = OrderItem.new(product: package, product_variant: variant, title: "Photo package - Standard", quantity: 1,
                         unit_price_cents: variant.price_cents, total_cents: variant.price_cents,
                         snapshot: OrderItem.catalog_snapshot(variant))

    package.update!(title: "New package title")
    component.update!(quantity: 4)
    service.update!(title: "Retitled photography", description: "New description", sla_days: 99)

    snapshot = item.snapshot.deep_symbolize_keys

    expect(snapshot).to include(product_title: "Photo package")
    expect(snapshot.fetch(:components)).to contain_exactly(
      hash_including(component_id: component.id, title: "Property photography", quantity: 1, sla_days: 2)
    )
  end

  it "does not provide a product-level square-foot field or JSON pricing array" do
    expect(Product.column_names).not_to include("sqft", "pricing", "price_tiers")
    expect(ProductVariant.column_names).to include("sqft_min", "sqft_max", "price_cents")
    expect(ProductComponent.column_names).not_to include("service_product_variant_id")
  end

  it "rejects an active tier that touches another active tier at the same boundary" do
    service.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 20_000, sqft_min: 0, sqft_max: 1_000)
    overlapping = service.product_variants.build(title: "From 1,000 sqft", price_cents: 30_000,
                                                  sqft_min: 1_000, sqft_max: 2_000)

    expect(overlapping).not_to be_valid
    expect(overlapping.errors.full_messages).to include("This range overlaps another active range.")
  end
end
