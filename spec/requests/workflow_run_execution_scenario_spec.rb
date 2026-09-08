require "rails_helper"

RSpec.describe "Workflow run execution API scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Execution API Agency", slug: "execution-api-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Execution API Agency", slug: "other-execution-api-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Execution manager", email: "execution-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Execution client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "3 Execution Street") }
  let!(:service) do
    organization.products.create!(slug: "execution-service", title: "Execution photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 25_000) }
  let!(:board) { organization.default_board }

  before do
    ActiveJob::Base.queue_adapter = :test
    board.board_workflows.update_all(enabled: false)
    sign_in manager
  end

  it "recovers a failed approval workflow through the retry API without duplicate production work" do
    post "/api/v1/boards/#{board.id}/workflows", params: {
      board_workflow: {
        name: "Execution workflow",
        trigger_key: "order_approved",
        enabled: true,
        status_mappings_attributes: BoardWorkflow.default_status_mapping_attributes(board),
        actions_attributes: [
          { action_type: "create_parent_task", configuration: { title: "Production" }, position: 0 },
          { action_type: "create_or_group_child_task", configuration: { customer_visible: true }, position: 1 },
          { action_type: "place_on_board", configuration: { board_id: board.id, column_key: "todo" }, position: 2 }
        ]
      }
    }
    expect(response).to have_http_status(:created)
    workflow = BoardWorkflow.find(response.parsed_body.dig("board_workflow", "id"))
    placement_action = workflow.actions.find_by!(action_type: "place_on_board")
    placement_action.update_columns(configuration: { "board_id" => other_organization.default_board.id, "column_key" => "todo" })

    post "/api/v1/orders", params: {
      order: {
        client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
        items: [ { product_variant_id: variant.id, quantity: 1 } ]
      }
    }
    expect(response).to have_http_status(:created)
    order_id = response.parsed_body.dig("order", "id")

    post "/api/v1/orders/#{order_id}/approve"
    expect(response).to have_http_status(:ok)
    run = workflow.runs.find_by!(order_id: order_id)

    expect { perform_enqueued_jobs(only: BoardWorkflowJob) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(run.reload).to be_failed
    expect(WorkflowTask.where(organization:).count).to eq(2)

    placement_action.update_columns(configuration: { "board_id" => board.id, "column_key" => "todo" })
    clear_enqueued_jobs
    post "/api/v1/boards/#{board.id}/workflow_runs/#{run.id}/retry"

    expect(response).to have_http_status(:accepted)
    expect(run.reload).to have_attributes(status: "pending", retry_count: 1)

    expect { perform_enqueued_jobs(only: BoardWorkflowJob) }.not_to raise_error

    expect(run.reload).to be_succeeded
    expect(run.steps.order(:position).pluck(:status)).to all(eq("succeeded"))
    expect(WorkflowTask.where(organization:).count).to eq(2)
    expect(WorkflowTaskPlacement.where(workflow_task: WorkflowTask.where(organization:)).count).to eq(2)
    expect(Order.find(order_id).order_deliverables.sole.workflow_tasks).to have_attributes(size: 1)
  end
end
