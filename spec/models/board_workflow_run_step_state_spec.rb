require "rails_helper"

RSpec.describe BoardWorkflowRunStep, type: :model do
  let!(:organization) { Organization.create!(name: "Run step agency", slug: "run-step-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Run step client", kind: :agent) }
  let!(:order) { Order.create!(organization:, client_account:, payment_mode: :pay_later) }
  let!(:workflow) do
    organization.default_board.board_workflows.create!(organization:, name: "Run step workflow",
                                                        trigger_key: "order_approved", enabled: false)
  end
  let!(:action) { workflow.actions.create!(action_type: "link_deliverable", position: 0) }
  let!(:run) do
    workflow.runs.create!(organization:, order:, idempotency_key: "run-step-#{SecureRandom.uuid}",
                          triggered_at: Time.current)
  end

  it "starts pending at position zero with empty input and output" do
    step = run.steps.build(board_workflow_action: action)

    expect(step).to have_attributes(status: "pending", position: 0, input: {}, output: {})
  end

  it "accepts every documented step state" do
    %w[running succeeded skipped failed].each do |status|
      step = run.steps.build(board_workflow_action: action, status:, position: 0)

      expect(step).to be_valid
    end
  end

  it "rejects an unknown state and a negative position" do
    step = run.steps.build(board_workflow_action: action, status: "paused", position: -1)

    expect(step).not_to be_valid
    expect(step.errors.full_messages).to include(
      "Status is not included in the list",
      "Position must be greater than or equal to 0"
    )
  end

  it "does not allow a run to record an action from another workflow" do
    other_workflow = organization.default_board.board_workflows.create!(organization:, name: "Other run step workflow",
                                                                          trigger_key: "order_approved", enabled: false)
    foreign_action = other_workflow.actions.create!(action_type: "link_deliverable", position: 0)
    step = run.steps.build(board_workflow_action: foreign_action, position: 0)

    expect(step).not_to be_valid
    expect(step.errors.full_messages).to include(
      "Board workflow action must belong to the run workflow"
    )
  end
end
