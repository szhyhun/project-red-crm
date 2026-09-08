require "rails_helper"

RSpec.describe "media workflow catalog rules" do
  let!(:organization) { Organization.create!(name: "Workflow Agency", slug: "workflow-catalog") }
  let!(:package) do
    Product.create!(organization:, slug: "photo-package", title: "Photo package", kind: :package,
                    deliverable_type: "other")
  end
  let!(:service) do
    Product.create!(organization:, slug: "photography", title: "Standard Property Photography", kind: :service,
                    deliverable_type: "photography", sla_days: 2)
  end

  it "uses relational variants for non-overlapping square-foot price tiers" do
    first = service.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 29_900, sqft_min: 0, sqft_max: 1_000)
    second = service.product_variants.create!(title: "1,001 to 2,000 sqft", price_cents: 39_900, sqft_min: 1_001, sqft_max: 2_000)

    expect(service.variant_for_sqft(1_000)).to eq(first)
    expect(service.variant_for_sqft(1_001)).to eq(second)
    expect(service).not_to respond_to(:sqft)
  end

  it "rejects an overlapping active tier instead of leaving checkout ambiguous" do
    service.product_variants.create!(title: "Base", price_cents: 29_900, sqft_min: 0, sqft_max: 1_000)
    overlap = service.product_variants.build(title: "Overlap", price_cents: 34_900, sqft_min: 900, sqft_max: 1_500)

    expect(overlap).not_to be_valid
    expect(overlap.errors.full_messages).to include("This range overlaps another active range.")
  end

  it "allows a service product to be sold alone and included in a package" do
    component = package.package_components.create!(organization:, service_product: service, quantity: 1, position: 0)

    expect(component).to be_persisted
    expect(service.service_components).to include(component)
    expect(component.service_product).to eq(service)
    expect(component).not_to respond_to(:product_variant)
  end

  it "rejects package nesting" do
    nested = package.package_components.build(organization:, service_product: package)

    expect(nested).not_to be_valid
    expect(nested.errors.full_messages).to include("Service product cannot be another package")
  end
end
