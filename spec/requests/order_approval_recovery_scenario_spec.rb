require "rails_helper"

RSpec.describe "Legacy order approval recovery API scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Approval recovery agency", slug: "approval-recovery-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Approval recovery manager", email: "approval-recovery-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Approval recovery client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "2 Approval Recovery Street") }
  let!(:service) do
    organization.products.create!(slug: "approval-recovery-service", title: "Approval recovery photography",
                                  kind: :service, deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 26_000) }
  let!(:order) do
    Orders::Create.call(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).fetch(:order)
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.update_all(enabled: false)
    sign_in manager
  end

  it "repairs an approved legacy order missing its approval timestamp and deliverables" do
    order.update_columns(status: "approved", approved_at: nil)

    expect {
      patch "/api/v1/orders/#{order.id}", params: { order: { status: "approved" } }
    }.to change { order.reload.order_deliverables.count }.from(0).to(1)

    expect(response).to have_http_status(:ok)
    expect(order.reload).to have_attributes(status: "approved", approved_at: be_present)
    expect(order.order_deliverables.sole).to have_attributes(
      service_product: service,
      scope_label: "Standard",
      status: "not_started"
    )
    expect(ActivityEvent.where(subject: order, event_type: "order.approved").count).to eq(1)
  end

  it "does not materialize a second time when a repaired order is approved again" do
    order.update_columns(status: "approved", approved_at: nil)
    patch "/api/v1/orders/#{order.id}", params: { order: { status: "approved" } }
    expect(response).to have_http_status(:ok)

    approved_at = order.reload.approved_at
    expect {
      patch "/api/v1/orders/#{order.id}", params: { order: { status: "approved" } }
    }.not_to change { order.reload.order_deliverables.count }

    expect(response).to have_http_status(:ok)
    expect(order.reload.approved_at).to eq(approved_at)
    expect(ActivityEvent.where(subject: order, event_type: "order.approved").count).to eq(1)
  end
end
