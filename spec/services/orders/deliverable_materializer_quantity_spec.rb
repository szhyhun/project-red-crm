require "rails_helper"

RSpec.describe Orders::DeliverableMaterializer do
  let!(:organization) { Organization.create!(name: "Quantity agency", slug: "quantity-materializer-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Quantity client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "12 Quantity Street") }
  let!(:photography) do
    organization.products.create!(slug: "quantity-photography", title: "Standard property photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:video) do
    organization.products.create!(slug: "quantity-video", title: "Standard property video", kind: :service,
                                  deliverable_type: "video", sla_days: 3)
  end
  let!(:package) do
    organization.products.create!(slug: "quantity-package", title: "Complete media package", kind: :package,
                                  deliverable_type: "other")
  end
  let!(:package_variant) do
    package.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 50_000, sqft_min: 0, sqft_max: 1_000)
  end
  let!(:service_variant) { photography.product_variants.create!(title: "Standard", price_cents: 30_000) }

  def approved_order(product:, variant:, quantity: 1, price_cents: variant.price_cents)
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                  status: :approved, approved_at: Time.zone.parse("2026-09-08 09:00:00")).tap do |order|
      order.order_items.create!(product:, product_variant: variant, title: product.title, quantity:,
                                unit_price_cents: price_cents, total_cents: price_cents * quantity)
    end
  end

  it "preserves both order-line quantity and included-service quantity" do
    component = package.package_components.create!(organization:, service_product: photography, quantity: 2, position: 0)
    order = approved_order(product: package, variant: package_variant, quantity: 3)

    deliverable = described_class.new(order:).call.sole

    expect(deliverable.metadata).to include("quantity" => 3, "component_quantity" => 2)
    expect(deliverable).to have_attributes(product_component: component, service_product: photography,
                                           scope_label: "0–1,000 sqft")
  end

  it "does not invent component quantity metadata for a standalone service" do
    order = approved_order(product: photography, variant: service_variant, quantity: 2)

    deliverable = described_class.new(order:).call.sole

    expect(deliverable.metadata).to include("quantity" => 2)
    expect(deliverable.metadata).not_to have_key("component_quantity")
    expect(deliverable.product_component).to be_nil
  end

  it "materializes each package component in position order with its own quantity" do
    photo_component = package.package_components.create!(organization:, service_product: photography, quantity: 1, position: 1)
    video_component = package.package_components.create!(organization:, service_product: video, quantity: 4, position: 0)
    order = approved_order(product: package, variant: package_variant)

    deliverables = described_class.new(order:).call

    expect(deliverables.map(&:service_product)).to eq([ video, photography ])
    expect(deliverables.map { |record| record.metadata.fetch("component_quantity") }).to eq([ 4, 1 ])
    expect(deliverables.map(&:product_component)).to eq([ video_component, photo_component ])
    expect(order.order_items.count).to eq(1)
  end
end
