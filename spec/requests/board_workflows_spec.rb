require "rails_helper"

RSpec.describe "Board workflow API", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Workflow API Agency", slug: "workflow-api-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Workflow Agency", slug: "other-workflow-api") }
  let!(:manager) do
    User.create!(organization:, name: "Workflow Manager", email: "workflow-api-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:staff) do
    User.create!(organization:, name: "Workflow Staff", email: "workflow-api-staff@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:board) { organization.default_board }
  let!(:workflow) do
    board.board_workflows.create!(organization:, name: "Production automation", trigger_key: "order_approved",
                                  created_by: manager, enabled: false).tap do |created_workflow|
      BoardWorkflow.default_status_mapping_attributes(board).each do |mapping|
        created_workflow.status_mappings.create!(mapping)
      end
      created_workflow.update!(enabled: true)
    end
  end
  let!(:action) do
    workflow.actions.create!(action_type: "create_parent_task", configuration: { "title" => "Production" }, position: 0)
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    sign_in manager
  end

  it "lists workflow definitions with their trigger and actions" do
    get "/api/v1/boards/#{board.id}/workflows"

    expect(response).to have_http_status(:ok)
    serialized = response.parsed_body.fetch("board_workflows").find { |entry| entry["id"] == workflow.id }
    expect(serialized).to include(
      "name" => "Production automation",
      "trigger_key" => "order_approved",
      "enabled" => true
    )
    expect(serialized.dig("actions", 0)).to include("id" => action.id, "action_type" => "create_parent_task")
  end

  it "creates a workflow with conditions and ordered actions" do
    expect {
      post "/api/v1/boards/#{board.id}/workflows", params: {
        board_workflow: {
          name: "Photography workflow",
          trigger_key: "order_approved",
          conditions_attributes: [
            { field: "deliverable_type", operator: "equals", value: "photography", position: 0 }
          ],
          actions_attributes: [
            { action_type: "create_or_group_child_task", configuration: { customer_visible: true }, position: 0 },
            { action_type: "place_on_board", configuration: { board_id: board.id, column_key: "todo" }, position: 1 }
          ],
          status_mappings_attributes: BoardWorkflow.default_status_mapping_attributes(board)
        }
      }
    }.to change(BoardWorkflow, :count).by(1)
      .and change(BoardWorkflowCondition, :count).by(1)
      .and change(BoardWorkflowAction, :count).by(2)

    expect(response).to have_http_status(:created)
    serialized = response.parsed_body.fetch("board_workflow")
    expect(serialized.fetch("conditions").sole).to include("field" => "deliverable_type", "operator" => "equals")
    expect(serialized.fetch("actions").pluck("action_type")).to eq([ "create_or_group_child_task", "place_on_board" ])
    expect(serialized.fetch("status_mappings").pluck("source_status")).to contain_exactly(
      "not_started", "in_progress", "in_review", "delivered"
    )
  end

  it "does not activate a workflow until every customer status has a mapping" do
    draft = board.board_workflows.create!(organization:, name: "Incomplete automation", trigger_key: "order_approved",
                                          created_by: manager, enabled: false)

    patch "/api/v1/boards/#{board.id}/workflows/#{draft.id}", params: {
      board_workflow: { enabled: true }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "status_mappings").join).to include("in_review")
    expect(draft.reload).not_to be_enabled
  end

  it "increments the workflow version when its behavior changes" do
    old_version = workflow.workflow_version

    patch "/api/v1/boards/#{board.id}/workflows/#{workflow.id}", params: {
      board_workflow: {
        name: "Updated production automation",
        actions_attributes: [ { id: action.id, configuration: { "title" => "Updated" } } ]
      }
    }

    expect(response).to have_http_status(:ok)
    expect(workflow.reload).to have_attributes(name: "Updated production automation", workflow_version: old_version + 1)
    expect(action.reload.configuration).to include("title" => "Updated")
  end

  it "increments the workflow version when status mappings change" do
    old_version = workflow.workflow_version

    patch "/api/v1/boards/#{board.id}/workflows/#{workflow.id}", params: {
      board_workflow: {
        status_mappings_attributes: [
          { id: workflow.status_mappings.find_by!(source_status: "delivered").id,
            source_status: "delivered", target_column_key: "done", position: 0 }
        ]
      }
    }

    expect(response).to have_http_status(:ok)
    expect(workflow.reload.workflow_version).to eq(old_version + 1)
    expect(workflow.status_mappings.find_by!(source_status: "delivered")).to have_attributes(target_column_key: "done")
  end

  it "returns workflow run details and steps to a board manager" do
    run = workflow.runs.create!(organization:, order: Order.create!(organization:, client_account: ClientAccount.create!(organization:, name: "Run Client", kind: :agent)),
                               idempotency_key: "workflow-api-run-#{SecureRandom.uuid}", triggered_at: Time.current)
    run.steps.create!(board_workflow_action: action, status: :succeeded, position: 0, output: { "task_id" => 10 })

    get "/api/v1/boards/#{board.id}/workflows/#{workflow.id}"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("board_workflow", "runs").sole).to include("id" => run.id, "status" => "pending")
  end

  it "does not let production staff create or change automations" do
    sign_out manager
    sign_in staff

    post "/api/v1/boards/#{board.id}/workflows", params: {
      board_workflow: { name: "Unauthorized", trigger_key: "order_approved" }
    }
    expect(response).to have_http_status(:forbidden)

    patch "/api/v1/boards/#{board.id}/workflows/#{workflow.id}", params: {
      board_workflow: { name: "Still unauthorized" }
    }
    expect(response).to have_http_status(:forbidden)
    expect(workflow.reload.name).to eq("Production automation")
  end

  it "does not let production staff inspect workflow definitions or run history" do
    run = workflow.runs.create!(organization:, order: Order.create!(organization:, client_account: ClientAccount.create!(organization:, name: "Inspect client", kind: :agent)),
                                status: :succeeded, idempotency_key: "inspect-run-#{SecureRandom.uuid}", triggered_at: Time.current)
    sign_out manager
    sign_in staff

    get "/api/v1/boards/#{board.id}/workflows"
    expect(response).to have_http_status(:forbidden)

    get "/api/v1/boards/#{board.id}/workflow_runs"
    expect(response).to have_http_status(:forbidden)
    expect(run.reload).to be_succeeded
  end

  it "hides another organization's workflow definitions" do
    other_board = other_organization.default_board

    get "/api/v1/boards/#{other_board.id}/workflows"

    expect(response).to have_http_status(:not_found)
  end

  it "queues a retry only for a failed run and increments its retry count" do
    client = ClientAccount.create!(organization:, name: "Retry Client", kind: :agent)
    order = Order.create!(organization:, client_account: client)
    run = workflow.runs.create!(organization:, order:, status: :failed, retry_count: 1,
                                idempotency_key: "retry-run-#{SecureRandom.uuid}", triggered_at: Time.current,
                                error: "temporary")

    expect {
      post "/api/v1/boards/#{board.id}/workflow_runs/#{run.id}/retry"
    }.to change { run.reload.retry_count }.from(1).to(2)

    expect(response).to have_http_status(:accepted)
    expect(run.reload).to have_attributes(status: "pending", completed_at: nil)
    expect(enqueued_jobs).to include(a_hash_including(job: BoardWorkflowJob, args: [ run.id ]))
  end

  it "does not retry a successful workflow run" do
    client = ClientAccount.create!(organization:, name: "Completed Retry Client", kind: :agent)
    run = workflow.runs.create!(organization:, order: Order.create!(organization:, client_account: client), status: :succeeded,
                                idempotency_key: "completed-retry-#{SecureRandom.uuid}", triggered_at: Time.current,
                                completed_at: Time.current)

    expect {
      post "/api/v1/boards/#{board.id}/workflow_runs/#{run.id}/retry"
    }.not_to change { run.reload.retry_count }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to eq("workflow_run_not_failed")
    expect(enqueued_jobs).to be_empty
  end

  it "does not let production staff retry a workflow run" do
    client = ClientAccount.create!(organization:, name: "Protected Retry Client", kind: :agent)
    run = workflow.runs.create!(organization:, order: Order.create!(organization:, client_account: client), status: :failed,
                                idempotency_key: "protected-retry-#{SecureRandom.uuid}", triggered_at: Time.current)
    sign_out manager
    sign_in staff

    post "/api/v1/boards/#{board.id}/workflow_runs/#{run.id}/retry"

    expect(response).to have_http_status(:forbidden)
    expect(run.reload).to have_attributes(status: "failed", retry_count: 0)
  end
end
