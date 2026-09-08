require "rails_helper"

RSpec.describe OrderDeliverable, type: :model do
  let!(:organization) { Organization.create!(name: "Deliverable Rules Agency", slug: "deliverable-rules-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Deliverable Rules", slug: "other-deliverable-rules") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Deliverable client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "8 Deliverable Street") }
  let!(:service) do
    organization.products.create!(slug: "deliverable-service", title: "Deliverable service", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 10_000) }
  let!(:order) { Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later) }
  let!(:order_item) do
    order.order_items.create!(product: service, product_variant: variant, title: "Deliverable service", quantity: 1,
                              unit_price_cents: 10_000, total_cents: 10_000)
  end
  let!(:deliverable) do
    order.order_deliverables.create!(organization:, listing:, order_item:, service_product: service,
                                     title: service.title, deliverable_type: service.deliverable_type, sla_days: 2,
                                     materialization_key: "deliverable-rules-#{SecureRandom.uuid}")
  end

  it "exposes only ready, final, customer-visible, non-hidden assets in order" do
    visible_late = deliverable.media_assets.create!(organization:, listing:, order:, order_item:, kind: :final,
                                                     status: :ready, source_url: "https://cdn.example.test/late.jpg",
                                                     filename: "late.jpg", content_type: "image/jpeg", position: 2,
                                                     customer_visible: true)
    visible_first = deliverable.media_assets.create!(organization:, listing:, order:, order_item:, kind: :final,
                                                      status: :ready, source_url: "https://cdn.example.test/first.jpg",
                                                      filename: "first.jpg", content_type: "image/jpeg", position: 1,
                                                      customer_visible: true)
    deliverable.media_assets.create!(organization:, listing:, order:, order_item:, kind: :raw, status: :ready,
                                     source_url: "https://cdn.example.test/raw.jpg", filename: "raw.jpg",
                                     content_type: "image/jpeg", customer_visible: true)
    deliverable.media_assets.create!(organization:, listing:, order:, order_item:, kind: :final, status: :pending,
                                     source_url: "https://cdn.example.test/pending.jpg", filename: "pending.jpg",
                                     content_type: "image/jpeg", customer_visible: true)
    deliverable.media_assets.create!(organization:, listing:, order:, order_item:, kind: :final, status: :ready,
                                     source_url: "https://cdn.example.test/hidden.jpg", filename: "hidden.jpg",
                                     content_type: "image/jpeg", customer_visible: true, hidden: true)

    expect(deliverable.customer_visible_assets).to eq([ visible_first, visible_late ])
  end

  it "accepts the permanent customer-facing delivery states" do
    expect(described_class.statuses.keys).to contain_exactly("not_started", "in_progress", "in_review", "delivered")

    expect { deliverable.update!(status: :in_review) }.not_to raise_error
    expect(deliverable).to be_in_review
  end

  it "rejects an invalid square-foot scope" do
    invalid = deliverable.dup
    invalid.materialization_key = "invalid-scope-#{SecureRandom.uuid}"
    invalid.scope_sqft_min = 2_001
    invalid.scope_sqft_max = 1_000

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include("Scope sqft max must be greater than or equal to the minimum square footage")
  end

  it "rejects a deliverable whose order belongs to another organization" do
    foreign_client = ClientAccount.create!(organization: other_organization, name: "Foreign client", kind: :agent)
    foreign_order = Order.new(organization: other_organization, client_account: foreign_client)
    invalid = deliverable.dup
    invalid.materialization_key = "foreign-order-#{SecureRandom.uuid}"
    invalid.order = foreign_order

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include("Order must belong to the same organization")
  end

  it "rejects a deliverable linked to a service from another organization" do
    foreign_service = other_organization.products.create!(slug: "foreign-deliverable-service", title: "Foreign service",
                                                           kind: :service, deliverable_type: "video")
    invalid = deliverable.dup
    invalid.materialization_key = "foreign-service-#{SecureRandom.uuid}"
    invalid.service_product = foreign_service

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include("Service product must belong to the same organization")
  end

  it "keeps materialization keys unique for retry-safe creation" do
    duplicate = deliverable.dup
    expect(duplicate).not_to be_valid
    expect(duplicate.errors.full_messages).to include("Materialization key has already been taken")
  end

  it "scopes active deliverables away from cancelled work" do
    cancelled = order.order_deliverables.create!(organization:, listing:, order_item:, service_product: service,
                                                  title: "Cancelled service", deliverable_type: "photography", sla_days: 0,
                                                  cancelled_at: Time.current,
                                                  materialization_key: "cancelled-#{SecureRandom.uuid}")

    expect(order.order_deliverables.active).not_to include(cancelled)
    expect(order.order_deliverables.active).to include(deliverable)
  end
end
