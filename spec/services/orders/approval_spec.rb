require "rails_helper"

RSpec.describe Orders::Approval do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Approval Agency", slug: "approval-workflow") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "111 Oak Bay Avenue") }
  let!(:service) do
    Product.create!(organization:, slug: "photo-service", title: "Photography", kind: :service,
                    deliverable_type: "photography", sla_days: 2)
  end
  let!(:package) do
    Product.create!(organization:, slug: "media-package", title: "Media package", kind: :package,
                    deliverable_type: "other").tap do |product|
      product.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 50_000, sqft_min: 0, sqft_max: 1_000)
      product.package_components.create!(organization:, service_product: service, quantity: 1, position: 0)
    end
  end
  let!(:order) do
    Orders::Creator.new(
      organization:,
      attributes: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: package.product_variants.first.id, quantity: 1 } ]
      }
    ).create!
  end

  before do
    ActiveJob::Base.queue_adapter = :test
  end

  it "approves once, creates scoped deliverables, and queues the board workflow" do
    expect {
      described_class.new(order:, actor: nil).call
    }.to change { order.reload.order_deliverables.count }.from(0).to(1)
      .and change(BoardWorkflowRun, :count).by(1)

    deliverable = order.reload.order_deliverables.sole
    expect(order).to be_approved
    expect(order.approved_at).to be_present
    expect(deliverable).to have_attributes(
      service_product_id: service.id,
      product_component_id: package.package_components.first.id,
      scope_sqft_min: 0,
      scope_sqft_max: 1_000,
      status: "not_started"
    )
    expect(deliverable.title).to eq("Photography")
    expect(enqueued_jobs.map { |job| job[:job] }).to include(BoardWorkflowJob)
  end

  it "is safe to retry after the deliverables and workflow run already exist" do
    described_class.new(order:, actor: nil).call
    clear_enqueued_jobs

    expect {
      described_class.new(order: order.reload, actor: nil).call
    }.not_to change { [ order.reload.order_deliverables.count, BoardWorkflowRun.count ] }
    expect(enqueued_jobs.map { |job| job[:job] }).to include(BoardWorkflowJob)
  end

  it "records one approval event per order and listing across retries" do
    described_class.new(order:, actor: nil).call

    expect {
      described_class.new(order: order.reload, actor: nil).call
    }.not_to change(ActivityEvent, :count)

    expect(ActivityEvent.where(subject: order, event_type: "order.approved").count).to eq(1)
    expect(ActivityEvent.where(subject: listing, event_type: "order.approved").count).to eq(1)
  end

  it "does not create a second invoice line for a package component" do
    described_class.new(order:, actor: nil).call

    expect(order.reload.order_items.count).to eq(1)
    expect(order.order_deliverables.count).to eq(1)
    expect(order.total_cents).to eq(50_000)
  end
end
