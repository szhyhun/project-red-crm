require "rails_helper"

RSpec.describe Workflows::ExecuteRun do
  let!(:organization) { Organization.create!(name: "Runner mapping agency", slug: "runner-mapping-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Runner mapping manager", email: "runner-mapping@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Runner mapping client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "10 Mapping Street") }
  let!(:board) { organization.default_board }
  let!(:service) do
    organization.products.create!(slug: "runner-mapping-service", title: "Mapping photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:order) do
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                  status: :approved, approved_at: Time.zone.parse("2026-09-07 09:00:00")).tap do |record|
      record.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                                 unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
    end
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }
  let!(:workflow) do
    board.board_workflows.create!(organization:, name: "Mapping workflow", trigger_key: "order_approved",
                                  enabled: false, created_by: manager)
  end
  let!(:run) do
    workflow.runs.create!(organization:, order:, idempotency_key: "mapping-#{SecureRandom.uuid}",
                          triggered_at: Time.current)
  end

  def add_action
    workflow.actions.create!(action_type: "create_or_group_child_task", configuration: {}, position: 0)
  end

  it "starts a review deliverable in the explicitly mapped review column" do
    review = board.workflow_columns.create!(organization:, key: "review", name: "Review", color: "#c9b6ff",
                                            category: :active, position: 4)
    deliverable.update!(status: :in_review)
    workflow.status_mappings.create!(source_status: "in_review", target_column_key: review.key, position: 0)
    add_action

    described_class.call(run:)

    task = WorkflowTask.where(task_kind: "deliverable").sole
    expect(task).to have_attributes(status: "review")
    expect(task.home_placement.workflow_column).to eq(review)
    expect(run.reload).to be_succeeded
  end

  it "starts an already delivered deliverable in the completed column" do
    deliverable.update!(status: :delivered, delivered_at: Time.current)
    workflow.status_mappings.create!(source_status: "delivered", target_column_key: "done", position: 0)
    add_action

    described_class.call(run:)

    task = WorkflowTask.where(task_kind: "deliverable").sole
    expect(task).to have_attributes(status: "done")
    expect(task.home_placement.workflow_column.key).to eq("done")
    expect(deliverable.reload).to be_delivered
  end

  it "falls back to the board's first column when a legacy mapping points elsewhere" do
    mapping = workflow.status_mappings.build(source_status: "not_started", target_column_key: "removed_column",
                                              position: 0)
    mapping.save!(validate: false)
    add_action

    described_class.call(run:)

    task = WorkflowTask.where(task_kind: "deliverable").sole
    expect(task).to have_attributes(status: "todo")
    expect(task.home_placement.workflow_column.key).to eq("todo")
    expect(run.reload).to be_succeeded
  end
end
