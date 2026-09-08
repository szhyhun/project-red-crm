require "rails_helper"

RSpec.describe "Workflow recovery API scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Workflow recovery agency", slug: "workflow-recovery-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Workflow recovery manager", email: "workflow-recovery-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Workflow recovery client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "71 Workflow Recovery Street") }
  let!(:service) do
    organization.products.create!(slug: "workflow-recovery-service", title: "Property photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 25_000) }
  let!(:order) do
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                  status: :approved, approved_at: Time.zone.parse("2026-09-08 09:00:00")).tap do |record|
      record.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                                 unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
    end
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }
  let!(:board) { organization.default_board }
  let!(:workflow) do
    board.board_workflows.create!(organization:, name: "Recoverable production workflow", trigger_key: "order_approved",
                                  created_by: manager, enabled: false).tap do |record|
      BoardWorkflow.default_status_mapping_attributes(board).each { |mapping| record.status_mappings.create!(mapping) }
    end
  end
  let!(:child_action) do
    workflow.actions.create!(action_type: "create_or_group_child_task", configuration: { "customer_visible" => true }, position: 0)
  end
  let!(:placement_action) do
    workflow.actions.build(action_type: "place_on_board", configuration: { "board_id" => 999_999, "column_key" => "todo" }, position: 1).tap do |record|
      # This represents a legacy row that bypassed the newer configuration validation.
      record.save!(validate: false)
    end
  end
  let!(:run) do
    workflow.runs.create!(organization:, order:, status: :pending,
                          idempotency_key: "recoverable-run-#{SecureRandom.uuid}", triggered_at: Time.current)
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.where(is_default: true).update_all(enabled: false)
    sign_in manager
  end

  it "records the failed action, then retries successfully without duplicating the task" do
    expect { BoardWorkflowJob.perform_now(run.id) }.to raise_error(ActiveRecord::RecordNotFound)

    expect(run.reload).to have_attributes(status: "failed", completed_at: be_present)
    expect(run.steps.order(:position).map(&:status)).to eq(%w[succeeded failed])
    expect(run.steps.order(:position).last.error).to include("ActiveRecord::RecordNotFound")
    expect(WorkflowTask.joins(:order_deliverables).where(order_deliverables: { id: deliverable.id }).count).to eq(1)

    placement_action.update!(configuration: { "board_id" => board.id, "column_key" => "todo" })

    perform_enqueued_jobs(only: BoardWorkflowJob) do
      post "/api/v1/boards/#{board.id}/workflow_runs/#{run.id}/retry"
    end

    expect(response).to have_http_status(:accepted)
    expect(run.reload).to have_attributes(status: "succeeded", error: nil, retry_count: 1)
    expect(WorkflowTask.joins(:order_deliverables).where(order_deliverables: { id: deliverable.id }).count).to eq(1)
    expect(run.steps.order(:position).map(&:status)).to eq(%w[succeeded succeeded])
    expect(run.steps.order(:position).last.output).to include("task_ids")
  end

  it "exposes failed step details before a manager retries the run" do
    expect { BoardWorkflowJob.perform_now(run.id) }.to raise_error(ActiveRecord::RecordNotFound)

    get "/api/v1/boards/#{board.id}/workflow_runs"

    expect(response).to have_http_status(:ok)
    serialized = response.parsed_body.fetch("board_workflow_runs").find { |entry| entry["id"] == run.id }
    expect(serialized).to include("status" => "failed", "error" => include("ActiveRecord::RecordNotFound"))
    expect(serialized.dig("steps", 1)).to include("status" => "failed", "error" => include("ActiveRecord::RecordNotFound"))
  end
end
