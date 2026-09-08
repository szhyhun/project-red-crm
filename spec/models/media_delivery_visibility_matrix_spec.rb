require "rails_helper"

RSpec.describe "media delivery visibility and lineage", type: :model do
  let!(:organization) { Organization.create!(name: "Visibility matrix agency", slug: "visibility-matrix-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Visibility client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "1 Visibility Street") }
  let!(:service) do
    organization.products.create!(slug: "visibility-photo", title: "Visibility photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:order) { Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later) }
  let!(:order_item) do
    order.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                              unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
  end
  let!(:deliverable) do
    order.order_deliverables.create!(organization:, listing:, order_item:, service_product: service,
                                     title: service.title, deliverable_type: service.deliverable_type, sla_days: 2,
                                     materialization_key: "visibility-deliverable-#{SecureRandom.uuid}")
  end
  let!(:other_deliverable) do
    order.order_deliverables.create!(organization:, listing:, order_item:, service_product: service,
                                     title: "Second photography pass", deliverable_type: service.deliverable_type,
                                     sla_days: 2, materialization_key: "visibility-second-#{SecureRandom.uuid}")
  end

  def create_asset(deliverable:, filename:, position: 0, version: 1, kind: :final, status: :ready,
                   customer_visible: true, hidden: false)
    deliverable.media_assets.create!(
      organization:, listing:, order:, order_item: deliverable.order_item, order_deliverable: deliverable,
      kind:, status:, storage_key: "organizations/#{organization.id}/#{filename}", filename:,
      content_type: "image/jpeg", byte_size: 5, position:, version:, customer_visible:, hidden:
    )
  end

  it "includes only current ready final visible assets in stable display order" do
    first = create_asset(deliverable:, filename: "first.jpg", position: 0)
    replacement_source = create_asset(deliverable:, filename: "old.jpg", position: 1)
    replacement = create_asset(deliverable:, filename: "replacement.jpg", position: 1, version: 2)
    replacement_source.update!(superseded_by: replacement)
    last = create_asset(deliverable:, filename: "last.jpg", position: 2)

    create_asset(deliverable:, filename: "pending.jpg", status: :pending)
    create_asset(deliverable:, filename: "processing.jpg", status: :processing)
    create_asset(deliverable:, filename: "failed.jpg", status: :failed)
    create_asset(deliverable:, filename: "raw.jpg", kind: :raw)
    create_asset(deliverable:, filename: "marketing.jpg", kind: :marketing)
    create_asset(deliverable:, filename: "hidden.jpg", hidden: true)

    expect(deliverable.customer_visible_assets).to eq([ first, replacement, last ])
  end

  it "does not mix assets from another deliverable on the same listing" do
    foreign_asset = create_asset(deliverable: other_deliverable, filename: "other-deliverable.jpg")

    expect(deliverable.customer_visible_assets).to be_empty
    expect(other_deliverable.customer_visible_assets).to contain_exactly(foreign_asset)
  end

  it "allows an unassigned asset to enter a deliverable once" do
    asset = MediaAsset.create!(organization:, listing:, order:, order_item:, kind: :final, status: :ready,
                               storage_key: "organizations/#{organization.id}/unassigned.jpg",
                               filename: "unassigned.jpg", content_type: "image/jpeg", byte_size: 5)

    expect { asset.update!(order_deliverable: deliverable) }.not_to raise_error
    expect(asset.reload.order_deliverable).to eq(deliverable)
  end

  it "does not allow a persisted asset to move to another deliverable" do
    asset = create_asset(deliverable:, filename: "immutable.jpg")

    expect(asset.update(order_deliverable: other_deliverable)).to be(false)
    expect(asset.errors.full_messages).to include("Order deliverable cannot be changed once assigned")
    expect(asset.reload.order_deliverable).to eq(deliverable)
  end

  it "does not allow a persisted asset to be detached from its deliverable" do
    asset = create_asset(deliverable:, filename: "attached.jpg")

    expect(asset.update(order_deliverable: nil)).to be(false)
    expect(asset.errors.full_messages).to include("Order deliverable cannot be changed once assigned")
    expect(asset.reload.order_deliverable).to eq(deliverable)
  end
end
