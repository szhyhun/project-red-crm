require "rails_helper"

RSpec.describe BoardWorkflow, type: :model do
  let!(:organization) { Organization.create!(name: "Workflow validation agency", slug: "workflow-validation-agency") }
  let!(:board) { organization.default_board }

  it "provides explicit mappings for every customer-facing deliverable state" do
    mappings = described_class.default_status_mapping_attributes(board)

    expect(mappings).to contain_exactly(
      { source_status: "not_started", target_column_key: "todo", position: 0 },
      { source_status: "in_progress", target_column_key: "in_progress", position: 1 },
      { source_status: "in_review", target_column_key: "in_progress", position: 2 },
      { source_status: "delivered", target_column_key: "done", position: 3 }
    )
  end

  it "rejects a new enabled workflow with incomplete customer-state mappings" do
    workflow = board.board_workflows.build(organization:, name: "Incomplete workflow", trigger_key: "order_approved")

    expect(workflow).not_to be_valid
    expect(workflow.errors[:status_mappings].sole).to include("in_review")
  end

  it "allows a disabled draft to be saved before its mappings are configured" do
    workflow = board.board_workflows.create!(organization:, name: "Draft workflow", trigger_key: "order_approved", enabled: false)

    expect(workflow).to be_persisted
    expect(workflow.missing_status_mappings).to contain_exactly(*OrderDeliverable::STATUSES)
  end

  it "requires complete mappings when a draft is activated" do
    workflow = board.board_workflows.create!(organization:, name: "Activating workflow", trigger_key: "order_approved", enabled: false)

    workflow.enabled = true

    expect(workflow).not_to be_valid
    expect(workflow.errors[:status_mappings].sole).to include("not_started")
  end

  it "keeps the first-column fallback available for legacy enabled workflows" do
    workflow = board.board_workflows.create!(organization:, name: "Legacy workflow", trigger_key: "order_approved", enabled: false)
    workflow.update_columns(enabled: true)

    expect(workflow.reload).to be_valid
    expect(workflow.missing_status_mappings).to contain_exactly(*OrderDeliverable::STATUSES)
  end
end
