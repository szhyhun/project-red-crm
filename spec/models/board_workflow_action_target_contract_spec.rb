require "rails_helper"

RSpec.describe BoardWorkflowAction, type: :model do
  let!(:organization) { Organization.create!(name: "Action target agency", slug: "action-target-agency") }
  let!(:other_organization) { Organization.create!(name: "Other action target agency", slug: "other-action-target-agency") }
  let!(:board) { organization.default_board }
  let!(:workflow) do
    board.board_workflows.create!(organization:, name: "Action target workflow", trigger_key: "order_approved", enabled: false)
  end

  it "allows a placement action to use the first column when no explicit column is configured" do
    action = workflow.actions.build(action_type: "place_on_board", configuration: { "board_id" => board.id }, position: 0)

    expect(action).to be_valid
  end

  it "rejects a placement action with an unknown column on a valid target board" do
    action = workflow.actions.build(
      action_type: "place_on_board", configuration: { "board_id" => board.id, "column_key" => "missing" }, position: 0
    )

    expect(action).not_to be_valid
    expect(action.errors[:configuration]).to include("target column must exist on the target board")
  end

  it "rejects a placement action with a column from another board" do
    other_board = other_organization.default_board
    action = workflow.actions.build(
      action_type: "place_on_board", configuration: { "board_id" => other_board.id, "column_key" => "todo" }, position: 0
    )

    expect(action).not_to be_valid
    expect(action.errors[:configuration]).to include("target board must belong to the workflow organization")
  end

  it "keeps a valid explicit placement target addressable" do
    action = workflow.actions.build(
      action_type: "place_on_board", configuration: { "board_id" => board.id, "column_key" => "in_progress" }, position: 0
    )

    expect(action).to be_valid
  end
end
