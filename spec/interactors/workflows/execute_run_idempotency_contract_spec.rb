require "rails_helper"

RSpec.describe Workflows::ExecuteRun do
  let!(:organization) { Organization.create!(name: "Runner contract agency", slug: "runner-contract-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Runner contract manager", email: "runner-contract-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Runner contract client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "9 Runner Contract Avenue") }
  let!(:service) do
    organization.products.create!(
      slug: "runner-contract-service",
      title: "Runner contract photography",
      kind: :service,
      deliverable_type: "photography",
      sla_days: 2
    )
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 18_000) }
  let!(:order) do
    Order.create!(
      organization:,
      client_account:,
      listing:,
      payment_mode: :pay_later,
      status: :approved,
      approved_at: Time.current
    ).tap do |record|
      record.order_items.create!(
        product: service,
        product_variant: variant,
        title: service.title,
        quantity: 1,
        unit_price_cents: variant.price_cents,
        total_cents: variant.price_cents,
        snapshot: OrderItem.catalog_snapshot(variant)
      )
    end
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }
  let!(:workflow) do
    organization.default_board.board_workflows.create!(
      organization:,
      name: "Runner contract workflow",
      trigger_key: "order_approved",
      enabled: false,
      created_by: manager
    )
  end
  let!(:run) do
    workflow.runs.create!(
      organization:,
      order:,
      idempotency_key: "runner-contract-#{SecureRandom.uuid}",
      triggered_at: Time.current
    )
  end

  it "does not duplicate work or rewrite a completed run when retried" do
    workflow.actions.create!(
      action_type: "create_or_group_child_task",
      configuration: { "customer_visible" => true },
      position: 0
    )

    expect { described_class.call(run:) }.to change(WorkflowTask, :count).by(1)

    completed_at = run.reload.completed_at
    task_id = deliverable.reload.workflow_tasks.sole.id
    step_id = run.steps.sole.id

    expect { described_class.call(run: run.reload) }.not_to change(WorkflowTask, :count)

    expect(run.reload).to have_attributes(status: "succeeded", completed_at:)
    expect(run.steps.reload).to contain_exactly(have_attributes(id: step_id, status: "succeeded"))
    expect(deliverable.reload.workflow_tasks.pluck(:id)).to eq([ task_id ])
  end

  it "records an unsupported legacy action as a warning without failing the run" do
    workflow.actions.build(
      action_type: "legacy_assign_to_queue",
      configuration: { "queue_id" => 42 },
      position: 0
    ).save!(validate: false)

    expect { described_class.call(run:) }.not_to change(WorkflowTask, :count)

    expect(run.reload).to be_succeeded_with_warnings
    expect(run.error).to include("Unsupported workflow action legacy_assign_to_queue")
    expect(run.steps.sole).to have_attributes(status: "skipped", error: nil)
    expect(run.steps.sole.output).to eq(
      "warning" => "Unsupported workflow action legacy_assign_to_queue"
    )
  end
end
