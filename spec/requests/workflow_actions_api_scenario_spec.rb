require "rails_helper"

RSpec.describe "workflow actions API scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Workflow actions agency", slug: "workflow-actions-agency") }
  let!(:other_organization) { Organization.create!(name: "Other workflow actions agency", slug: "other-workflow-actions-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Workflow actions manager", email: "workflow-actions-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:assignee) do
    User.create!(organization:, name: "Workflow actions assignee", email: "workflow-actions-assignee@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Workflow actions client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "3 Workflow Actions Street") }
  let!(:service) do
    organization.products.create!(slug: "workflow-actions-service", title: "Workflow photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 28_000) }
  let!(:group) { organization.user_groups.create!(name: "Photographers") }
  let!(:secondary_board) do
    organization.boards.create!(name: "Delivery review", kind: :internal, visibility: :organization,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:board) { organization.default_board }

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.update_all(enabled: false)
    sign_in manager
  end

  def workflow_attributes(actions:)
    {
      board_workflow: {
        name: "Configured workflow",
        description: "Routes purchased production work.",
        trigger_key: "order_approved",
        enabled: true,
        status_mappings_attributes: BoardWorkflow.default_status_mapping_attributes(board),
        actions_attributes: actions
      }
    }
  end

  def create_order
    post "/api/v1/orders", params: {
      order: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: variant.id, quantity: 1 } ]
      }
    }
    expect(response).to have_http_status(:created)
    Order.find(response.parsed_body.dig("order", "id"))
  end

  it "executes configured actions from the API and records each output" do
    post "/api/v1/boards/#{board.id}/workflows", params: workflow_attributes(actions: [
      { action_type: "create_parent_task", configuration: { title: "Production" }, position: 0 },
      { action_type: "create_or_group_child_task", configuration: { customer_visible: true }, position: 1 },
      { action_type: "assign_to_user", configuration: { user_id: assignee.id }, position: 2 },
      { action_type: "assign_to_group", configuration: { user_group_id: group.id }, position: 3 },
      { action_type: "place_on_board", configuration: { board_id: secondary_board.id, column_key: "in_progress" }, position: 4 }
    ])

    expect(response).to have_http_status(:created)
    workflow = BoardWorkflow.find(response.parsed_body.dig("board_workflow", "id"))
    order = create_order

    perform_enqueued_jobs(only: BoardWorkflowJob) do
      post "/api/v1/orders/#{order.id}/approve"
    end

    expect(response).to have_http_status(:ok)
    run = workflow.runs.find_by!(order:)
    task = WorkflowTask.where(organization:, task_kind: "deliverable").sole
    secondary_placement = task.workflow_task_placements.find_by!(board: secondary_board)

    expect(run).to be_succeeded
    expect(run.steps.order(:position).pluck(:status)).to all(eq("succeeded"))
    expect(run.steps.order(:position).map { |step| step.output.keys }).to include(
      include("task_ids"), include("user_id"), include("user_group_id"), include("board_id")
    )
    expect(task).to have_attributes(assignee:, customer_visible: true)
    expect(task.metadata.fetch("assigned_group_id")).to eq(group.id)
    expect(secondary_placement).to have_attributes(
      is_home: false,
      workflow_column: secondary_board.workflow_columns.find_by!(key: "in_progress")
    )
    expect(task.order_deliverables).to contain_exactly(order.order_deliverables.sole)
  end

  it "does not duplicate action results when the same approved order is retried" do
    post "/api/v1/boards/#{board.id}/workflows", params: workflow_attributes(actions: [
      { action_type: "create_or_group_child_task", configuration: {}, position: 0 }
    ])
    expect(response).to have_http_status(:created)
    order = create_order

    perform_enqueued_jobs(only: BoardWorkflowJob) do
      post "/api/v1/orders/#{order.id}/approve"
    end
    expect(response).to have_http_status(:ok)
    clear_enqueued_jobs
    counts = [ WorkflowTask.count, WorkflowTaskPlacement.count, WorkflowTaskDeliverable.count, BoardWorkflowRun.count ]

    post "/api/v1/orders/#{order.id}/approve"

    expect(response).to have_http_status(:ok)
    expect([ WorkflowTask.count, WorkflowTaskPlacement.count, WorkflowTaskDeliverable.count, BoardWorkflowRun.count ]).to eq(counts)
    expect(enqueued_jobs).to be_empty
  end

  it "rejects a workflow action that targets another organization's board" do
    foreign_board = other_organization.default_board

    post "/api/v1/boards/#{board.id}/workflows", params: workflow_attributes(actions: [
      { action_type: "place_on_board", configuration: { board_id: foreign_board.id, column_key: "todo" }, position: 0 }
    ])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "actions.configuration").join).to include(
      "target board must belong to the workflow organization"
    )
    expect(board.board_workflows.find_by(name: "Configured workflow")).to be_nil
  end

  it "does not let production staff configure or read workflow definitions" do
    sign_out manager
    sign_in assignee

    post "/api/v1/boards/#{board.id}/workflows", params: workflow_attributes(actions: [])

    expect(response).to have_http_status(:forbidden)

    get "/api/v1/boards/#{board.id}/workflows"

    expect(response).to have_http_status(:forbidden)
  end
end
