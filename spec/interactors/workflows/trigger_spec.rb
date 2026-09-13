require "rails_helper"

RSpec.describe Workflows::Trigger, type: :interactor do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Trigger Agency", slug: "trigger-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Trigger Agency", slug: "other-trigger-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Trigger client", kind: :agent) }
  let!(:order) { Order.create!(organization:, client_account:, payment_mode: :pay_later) }
  let!(:workflow) do
    board = organization.default_board
    board.board_workflows.create!(organization:, name: "Trigger workflow", trigger_key: "order_approved", enabled: false).tap do |created_workflow|
      BoardWorkflow.default_status_mapping_attributes(board).each do |mapping|
        created_workflow.status_mappings.create!(mapping)
      end
      created_workflow.update!(enabled: true)
    end
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.where(is_default: true).update_all(enabled: false)
  end

  it "creates a pending run and queues the workflow job for an enabled workflow" do
    expect {
      described_class.call(order:)
    }.to change(BoardWorkflowRun, :count).by(1)

    run = BoardWorkflowRun.order(:id).last
    expect(run).to have_attributes(organization:, board_workflow: workflow, order:, status: "pending")
    expect(enqueued_jobs).to include(a_hash_including(job: BoardWorkflowJob, args: [ run.id ]))
  end

  it "does not create a run for a disabled workflow" do
    workflow.update!(enabled: false)

    expect {
      described_class.call(order:)
    }.not_to change(BoardWorkflowRun, :count)
    expect(enqueued_jobs).to be_empty
  end

  it "reuses the same run when approval is retried at the same workflow version" do
    trigger = described_class

    trigger.call(order:)
    trigger.call(order:)

    expect(BoardWorkflowRun.where(board_workflow: workflow, order:).count).to eq(1)
    expect(BoardWorkflowRun.order(:id).last.idempotency_key).to eq(
      "order-#{order.id}-workflow-#{workflow.id}-version-#{workflow.workflow_version}"
    )
  end

  it "creates a new run when the workflow version changes" do
    trigger = described_class
    trigger.call(order:)
    workflow.update!(workflow_version: workflow.workflow_version + 1)

    trigger.call(order:)

    expect(BoardWorkflowRun.where(board_workflow: workflow, order:).count).to eq(2)
    expect(BoardWorkflowRun.pluck(:idempotency_key)).to include(
      "order-#{order.id}-workflow-#{workflow.id}-version-1",
      "order-#{order.id}-workflow-#{workflow.id}-version-2"
    )
  end

  it "does not run another organization's workflow against this organization's order" do
    workflow.update!(enabled: false)

    expect {
      described_class.call(order:)
    }.not_to change(BoardWorkflowRun, :count)
    expect(enqueued_jobs).to be_empty
  end

  it "does not enqueue a second job for an already completed run" do
    run = workflow.runs.create!(organization:, order:, status: :succeeded,
                                idempotency_key: "completed-trigger-#{SecureRandom.uuid}", triggered_at: Time.current)
    allow(BoardWorkflowRun).to receive(:find_or_create_by!).and_return(run)

    described_class.call(order:)

    expect(enqueued_jobs).to be_empty
  end
end
