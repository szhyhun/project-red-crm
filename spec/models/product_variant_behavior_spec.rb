require "rails_helper"

RSpec.describe "Product variant selection", type: :model do
  let!(:organization) { Organization.create!(name: "Variant behavior agency", slug: "variant-behavior") }
  let!(:service) do
    organization.products.create!(slug: "variant-service", title: "Property photography", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:small) do
    service.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 29_900, sqft_min: 0, sqft_max: 1_000)
  end
  let!(:large) do
    service.product_variants.create!(title: "1,001 to 2,000 sqft", price_cents: 39_900, sqft_min: 1_001, sqft_max: 2_000)
  end
  let!(:open_ended) do
    service.product_variants.create!(title: "2,001+ sqft", price_cents: 49_900, sqft_min: 2_001)
  end

  it "selects a tier at both inclusive range boundaries" do
    expect(service.variant_for_sqft(0)).to eq(small)
    expect(service.variant_for_sqft(1_000)).to eq(small)
    expect(service.variant_for_sqft(1_001)).to eq(large)
    expect(service.variant_for_sqft(2_000)).to eq(large)
    expect(service.variant_for_sqft(2_001)).to eq(open_ended)
    expect(service.variant_for_sqft(50_000)).to eq(open_ended)
  end

  it "ignores inactive tiers during checkout selection" do
    small.update!(active: false)

    expect(service.variant_for_sqft(500)).to be_nil
    expect(service.variant_for_sqft(1_500)).to eq(large)
  end

  it "uses an active no-range variant as the fallback for non-area services" do
    fallback = service.product_variants.create!(title: "Any size", price_cents: 49_900)

    expect(service.variant_for_sqft(nil)).to eq(fallback)
  end

  it "allows overlapping inactive historical tiers" do
    small.update!(active: false)
    historical = service.product_variants.build(title: "Legacy overlapping tier", price_cents: 19_900,
                                                 sqft_min: 500, sqft_max: 1_500, active: false)

    expect(historical).to be_valid
  end

  it "rejects an active tier that overlaps an open-ended tier" do
    overlapping = service.product_variants.build(title: "3,000 to 4,000 sqft", price_cents: 59_900,
                                                  sqft_min: 3_000, sqft_max: 4_000)

    expect(overlapping).not_to be_valid
    expect(overlapping.errors.full_messages).to include("This range overlaps another active range.")
  end

  it "supports a maximum-only tier for properties up to a fixed size" do
    upper_bound_service = organization.products.create!(slug: "upper-bound-service", title: "Upper bound service",
                                                         kind: :service, deliverable_type: "photography")
    tier = upper_bound_service.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 19_900, sqft_max: 1_000)

    expect(upper_bound_service.variant_for_sqft(0)).to eq(tier)
    expect(upper_bound_service.variant_for_sqft(1_000)).to eq(tier)
    expect(upper_bound_service.variant_for_sqft(1_001)).to be_nil
  end

  it "rejects a reversed range before it can be sold" do
    invalid = service.product_variants.build(title: "Reversed", price_cents: 10_000, sqft_min: 2_000, sqft_max: 1_000)

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include(
      "Sqft max must be greater than or equal to the minimum square footage"
    )
  end

  it "does not add a product-level square-foot field" do
    expect(Product.column_names).not_to include("sqft")
    expect(Product.new).not_to respond_to(:sqft)
  end
end
