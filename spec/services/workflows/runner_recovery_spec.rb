require "rails_helper"

RSpec.describe Workflows::Runner do
  let!(:organization) { Organization.create!(name: "Recovery Agency", slug: "recovery-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Recovery Agency", slug: "other-recovery-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Recovery manager", email: "recovery-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Recovery client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "2 Recovery Street") }
  let!(:board) { organization.default_board }
  let!(:service) do
    organization.products.create!(slug: "recovery-service", title: "Recovery photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:order) do
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                  status: :approved, approved_at: Time.current).tap do |record|
      record.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                                 unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
    end
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }
  let!(:workflow) do
    board.board_workflows.create!(organization:, name: "Recovery workflow", trigger_key: "order_approved",
                                  created_by: manager, enabled: false)
  end
  let!(:run) do
    workflow.runs.create!(organization:, order:, idempotency_key: "recovery-#{SecureRandom.uuid}",
                          triggered_at: Time.current)
  end

  it "retries a failed run without duplicating the tasks or placements already created" do
    workflow.actions.create!(action_type: "create_parent_task", configuration: { "title" => "Production" }, position: 0)
    workflow.actions.create!(action_type: "create_or_group_child_task", configuration: {}, position: 1)
    workflow.actions.create!(action_type: "link_deliverable", configuration: {}, position: 2)
    broken_action = workflow.actions.build(
      action_type: "place_on_board", configuration: { "board_id" => other_organization.default_board.id, "column_key" => "todo" },
      position: 3
    )
    broken_action.save!(validate: false)

    expect { described_class.new(run:).call }.to raise_error(ActiveRecord::RecordNotFound)

    expect(run.reload).to be_failed
    expect(run.steps.order(:position).pluck(:status)).to eq(%w[succeeded succeeded succeeded failed])
    expect(WorkflowTask.where(organization:).count).to eq(2)
    expect(WorkflowTaskPlacement.where(workflow_task: WorkflowTask.where(organization:)).count).to eq(2)
    expect(WorkflowTaskDeliverable.where(order_deliverable: deliverable).count).to eq(1)

    broken_action.update_columns(configuration: { "board_id" => board.id, "column_key" => "todo" })
    run.update!(status: :pending, error: nil, completed_at: nil)

    expect { described_class.new(run: run.reload).call }.not_to raise_error

    expect(run.reload).to be_succeeded
    expect(run.steps.order(:position).pluck(:status)).to all(eq("succeeded"))
    expect(WorkflowTask.where(organization:).count).to eq(2)
    expect(WorkflowTaskPlacement.where(workflow_task: WorkflowTask.where(organization:)).count).to eq(2)
    expect(WorkflowTaskDeliverable.where(order_deliverable: deliverable).count).to eq(1)
  end

  it "records a warning instead of creating a parent task when a production board requires a listing" do
    order_without_listing = Order.create!(organization:, client_account:, payment_mode: :pay_later,
                                           status: :approved, approved_at: Time.current)
    order_without_listing.order_items.create!(product: service, product_variant: variant, title: service.title,
                                               quantity: 1, unit_price_cents: variant.price_cents,
                                               total_cents: variant.price_cents)
    Orders::DeliverableMaterializer.new(order: order_without_listing).call
    warning_workflow = board.board_workflows.create!(organization:, name: "Listing required workflow",
                                                     trigger_key: "order_approved", created_by: manager, enabled: false)
    warning_workflow.actions.create!(action_type: "create_parent_task", configuration: {}, position: 0)
    warning_run = warning_workflow.runs.create!(organization:, order: order_without_listing,
                                                idempotency_key: "warning-#{SecureRandom.uuid}", triggered_at: Time.current)

    described_class.new(run: warning_run).call

    expect(warning_run.reload).to be_succeeded_with_warnings
    expect(warning_run.error).to include("No listing is available")
    expect(warning_run.steps.sole).to have_attributes(status: "skipped")
    expect(WorkflowTask.where(workflow_group_key: "workflow:#{warning_run.id}:parent")).to be_empty
  end
end
