require "rails_helper"

RSpec.describe "Board workflow runs API", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Workflow run agency", slug: "workflow-run-agency") }
  let!(:other_organization) { Organization.create!(name: "Other workflow run agency", slug: "other-workflow-run-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Run manager", email: "workflow-run-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Run client", kind: :agent) }
  let!(:order) { Order.create!(organization:, client_account:, payment_mode: :pay_later) }
  let!(:board) { organization.default_board }
  let!(:workflow) do
    board.board_workflows.create!(organization:, name: "Run history workflow", trigger_key: "order_approved",
                                  enabled: false)
  end
  let!(:action) { workflow.actions.create!(action_type: "create_parent_task", configuration: {}, position: 0) }
  let!(:run) do
    workflow.runs.create!(organization:, order:, status: :succeeded,
                          idempotency_key: "run-history-#{SecureRandom.uuid}", triggered_at: 1.hour.ago,
                          started_at: 50.minutes.ago, completed_at: 45.minutes.ago)
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    run.steps.create!(board_workflow_action: action, status: :succeeded, position: 0,
                      input: { "title" => "Production" }, output: { "task_id" => 101 })
    sign_in manager
  end

  it "lists recent runs with their step input and output" do
    get "/api/v1/boards/#{board.id}/workflow_runs"

    expect(response).to have_http_status(:ok)
    serialized = response.parsed_body.fetch("board_workflow_runs").find { |entry| entry["id"] == run.id }
    expect(serialized).to include(
      "board_workflow_id" => workflow.id,
      "order_id" => order.id,
      "status" => "succeeded",
      "retry_count" => 0
    )
    expect(serialized.dig("steps", 0)).to include(
      "board_workflow_action_id" => action.id,
      "status" => "succeeded",
      "input" => { "title" => "Production" },
      "output" => { "task_id" => 101 }
    )
  end

  it "requeues a failed run and increments its retry count" do
    run.update!(status: :failed, error: "temporary worker failure")

    post "/api/v1/boards/#{board.id}/workflow_runs/#{run.id}/retry"

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body.fetch("board_workflow_run")).to include(
      "id" => run.id,
      "status" => "pending",
      "retry_count" => 1,
      "completed_at" => nil
    )
    expect(run.reload).to have_attributes(status: "pending", retry_count: 1, completed_at: nil)
    expect(enqueued_jobs).to include(a_hash_including(job: BoardWorkflowJob, args: [ run.id ]))
  end

  it "does not retry a run that has already completed" do
    post "/api/v1/boards/#{board.id}/workflow_runs/#{run.id}/retry"

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq("error" => "workflow_run_not_failed")
    expect(run.reload).to have_attributes(status: "succeeded", retry_count: 0)
    expect(enqueued_jobs).to be_empty
  end

  it "does not expose runs from a restricted board the manager cannot access" do
    restricted_board = organization.boards.create!(name: "Private run board", kind: :internal,
                                                    visibility: :restricted, requires_listing: false,
                                                    client_visible: false, position: 1)
    WorkflowColumn::DEFAULTS.each { |attributes| restricted_board.workflow_columns.create!(attributes.merge(organization:)) }
    restricted_workflow = restricted_board.board_workflows.create!(organization:, name: "Private workflow",
                                                                    trigger_key: "order_approved", enabled: false)
    private_run = restricted_workflow.runs.create!(organization:, order:, status: :failed,
                                                   idempotency_key: "private-run-#{SecureRandom.uuid}",
                                                   triggered_at: Time.current, error: "private failure")

    get "/api/v1/boards/#{restricted_board.id}/workflow_runs"
    expect(response).to have_http_status(:not_found)

    post "/api/v1/boards/#{restricted_board.id}/workflow_runs/#{private_run.id}/retry"
    expect(response).to have_http_status(:not_found)
    expect(private_run.reload).to be_failed
  end

  it "does not resolve a foreign organization's run through a local board" do
    foreign_board = other_organization.default_board
    foreign_client = ClientAccount.create!(organization: other_organization, name: "Foreign run client", kind: :agent)
    foreign_order = Order.create!(organization: other_organization, client_account: foreign_client)
    foreign_workflow = foreign_board.board_workflows.create!(organization: other_organization,
                                                              name: "Foreign workflow", trigger_key: "order_approved",
                                                              enabled: false)
    foreign_run = foreign_workflow.runs.create!(organization: other_organization, order: foreign_order, status: :failed,
                                                idempotency_key: "foreign-run-#{SecureRandom.uuid}",
                                                triggered_at: Time.current, error: "foreign failure")

    post "/api/v1/boards/#{board.id}/workflow_runs/#{foreign_run.id}/retry"

    expect(response).to have_http_status(:not_found)
    expect(foreign_run.reload).to be_failed
    expect(enqueued_jobs).to be_empty
  end
end
