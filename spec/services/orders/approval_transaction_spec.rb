require "rails_helper"

RSpec.describe Orders::Approve do
  let!(:organization) { Organization.create!(name: "Approval transaction agency", slug: "approval-transaction-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Approval transaction manager", email: "approval-transaction@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Approval transaction client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "70 Approval Transaction Street") }
  let!(:service) do
    organization.products.create!(slug: "approval-transaction-service", title: "Approval transaction photos",
                                  kind: :service, deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 25_000) }
  let!(:order) do
    Orders::Creator.new(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).create!
  end

  it "rolls back approval, deliverables, and activity when materialization fails" do
    materializer = instance_double(Orders::DeliverableMaterializer)
    allow(Orders::DeliverableMaterializer).to receive(:new).with(order: order).and_return(materializer)
    allow(materializer).to receive(:call).and_raise(ActiveRecord::RecordInvalid.new(order))

    expect {
      described_class.call(order:, actor: manager)
    }.to raise_error(ActiveRecord::RecordInvalid)

    expect(order.reload).to have_attributes(status: "draft", approved_at: nil)
    expect(order.order_deliverables).to be_empty
    expect(ActivityEvent.where(subject: order, event_type: "order.approved")).to be_empty
  end

  it "enqueues workflow materialization only after approval commits" do
    trigger = instance_double(Workflows::Trigger, enqueue!: true)
    allow(Workflows::Trigger).to receive(:new).and_return(trigger)

    described_class.call(order:, actor: manager)

    expect(Workflows::Trigger).to have_received(:new).with(order: have_attributes(id: order.id, status: "approved"))
    expect(trigger).to have_received(:enqueue!)
  end

  it "records the approving actor on both order and listing activity" do
    described_class.call(order:, actor: manager)

    expect(ActivityEvent.where(event_type: "order.approved").where(actor: manager).count).to eq(2)
    expect(ActivityEvent.where(subject: order, event_type: "order.approved").sole.payload).to include(
      "order_id" => order.id
    )
    expect(ActivityEvent.where(subject: listing, event_type: "order.approved").sole.payload).to include(
      "order_id" => order.id
    )
  end
end
