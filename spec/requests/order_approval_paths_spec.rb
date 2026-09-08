require "rails_helper"

RSpec.describe "Order approval paths", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Approval paths agency", slug: "approval-paths-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Approval paths manager", email: "approval-paths-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Approval paths client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "50 Approval Paths Street") }
  let!(:service) do
    organization.products.create!(slug: "approval-paths-service", title: "Approval paths photography",
                                  kind: :service, deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 28_000) }
  let!(:workflow) do
    organization.default_board.board_workflows.create!(organization:, name: "Approval paths workflow",
                                                        trigger_key: "order_approved", enabled: false).tap do |record|
      BoardWorkflow.default_status_mapping_attributes(record.board).each do |mapping|
        record.status_mappings.create!(mapping)
      end
      record.actions.create!(action_type: "create_or_group_child_task", configuration: {}, position: 0)
      record.update!(enabled: true)
    end
  end
  let!(:order) do
    Orders::Creator.new(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).create!
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.where.not(id: workflow.id).update_all(enabled: false)
    sign_in manager
  end

  it "uses the same approval service when status is changed through PATCH" do
    expect {
      patch "/api/v1/orders/#{order.id}", params: { order: { status: "approved" } }
    }.to change { order.reload.order_deliverables.count }.from(0).to(1)
      .and change(BoardWorkflowRun, :count).by(1)

    expect(response).to have_http_status(:ok)
    expect(order.reload).to have_attributes(status: "approved", approved_at: be_present)
    expect(order.order_deliverables.sole).to have_attributes(service_product: service, status: "not_started")
    expect(enqueued_jobs).to include(a_hash_including(job: BoardWorkflowJob))
  end

  it "does not materialize another deliverable when canonical approval follows PATCH approval" do
    patch "/api/v1/orders/#{order.id}", params: { order: { status: "approved" } }
    expect(response).to have_http_status(:ok)
    clear_enqueued_jobs
    original_approved_at = order.reload.approved_at

    post "/api/v1/orders/#{order.id}/approve"

    expect(response).to have_http_status(:ok)
    expect(order.reload).to have_attributes(status: "approved", approved_at: original_approved_at)
    expect(order.order_deliverables.count).to eq(1)
    expect(BoardWorkflowRun.where(order:).count).to eq(1)
    expect(enqueued_jobs).to include(a_hash_including(job: BoardWorkflowJob))
  end

  it "does not treat a normal update as another approval after the order is approved" do
    post "/api/v1/orders/#{order.id}/approve"
    expect(response).to have_http_status(:ok)
    clear_enqueued_jobs
    run_count = BoardWorkflowRun.where(order:).count
    approved_at = order.reload.approved_at

    patch "/api/v1/orders/#{order.id}", params: { order: { status: "approved", fee_cents: 500 } }

    expect(response).to have_http_status(:ok)
    expect(order.reload).to have_attributes(status: "approved", approved_at:, fee_cents: 500)
    expect(order.order_deliverables.count).to eq(1)
    expect(BoardWorkflowRun.where(order:).count).to eq(run_count)
  end
end
