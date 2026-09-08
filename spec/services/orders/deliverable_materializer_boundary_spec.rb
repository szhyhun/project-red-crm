require "rails_helper"

RSpec.describe Orders::DeliverableMaterializer do
  let!(:organization) { Organization.create!(name: "Boundary Agency", slug: "boundary-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Boundary client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "20 Boundary Street") }
  let!(:photo_service) do
    organization.products.create!(slug: "boundary-photo", title: "Boundary photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end

  def approved_order(listing: self.listing, approved_at: Time.zone.parse("2026-09-07 09:00:00"))
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                  status: :approved, approved_at:)
  end

  def add_item(order, product:, variant: nil, title: product.title, price_cents: 10_000, snapshot: {})
    order.order_items.create!(product:, product_variant: variant, title:, quantity: 1,
                              unit_price_cents: price_cents, total_cents: price_cents, snapshot:)
  end

  it "materializes an add-on as an independently delivered service" do
    addon = organization.products.create!(slug: "boundary-addon", title: "Twilight add-on", kind: :addon,
                                           deliverable_type: "files", sla_days: 1)
    variant = addon.product_variants.create!(title: "Twilight", price_cents: 7_500)
    order = approved_order
    item = add_item(order, product: addon, variant:, title: "Twilight add-on", price_cents: 7_500)

    deliverable = described_class.new(order:).call.sole

    expect(deliverable).to have_attributes(service_product: addon, product_component: nil, order_item: item,
                                           deliverable_type: "files", scope_label: "Twilight")
  end

  it "skips weekends when calculating a business-day target" do
    variant = photo_service.product_variants.create!(title: "Standard", price_cents: 10_000)
    order = approved_order(approved_at: Time.zone.parse("2026-09-11 09:00:00"))
    add_item(order, product: photo_service, variant:, price_cents: 10_000)

    deliverable = described_class.new(order:).call.sole

    # Friday plus two business days is Tuesday, not Sunday.
    expect(deliverable.target_on).to eq(Date.new(2026, 9, 15))
  end

  it "uses the sold order snapshot instead of a mutable catalog tier" do
    variant = photo_service.product_variants.create!(title: "Current tier", price_cents: 10_000,
                                                     sqft_min: 1_001, sqft_max: 2_000)
    order = approved_order
    add_item(order, product: photo_service, variant:, price_cents: 10_000,
             snapshot: { "variant_title" => "Sold tier", "sqft_min" => 0, "sqft_max" => 1_000,
                         "quantity_label" => "Standard home" })
    variant.update!(title: "Changed tier", sqft_min: 2_001, sqft_max: 3_000)

    deliverable = described_class.new(order:).call.sole

    expect(deliverable).to have_attributes(scope_sqft_min: 0, scope_sqft_max: 1_000, scope_label: "Standard home")
  end

  it "keeps internal orders without listings materializable" do
    order = approved_order(listing: nil)
    add_item(order, product: photo_service, price_cents: 10_000)

    deliverable = described_class.new(order:).call.sole

    expect(deliverable).to have_attributes(listing: nil, order_id: order.id, service_product: photo_service)
  end

  it "ignores a legacy order line whose catalog product was removed" do
    order = approved_order
    order.order_items.create!(title: "Legacy line", quantity: 1, unit_price_cents: 5_000, total_cents: 5_000)

    expect { described_class.new(order:).call }.not_to raise_error
    expect(described_class.new(order:).call).to be_empty
  end
end
