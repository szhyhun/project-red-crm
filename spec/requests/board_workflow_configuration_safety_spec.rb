require "rails_helper"

RSpec.describe "Board workflow configuration safety API", type: :request do
  let!(:organization) { Organization.create!(name: "Workflow safety agency", slug: "workflow-safety-agency") }
  let!(:other_organization) { Organization.create!(name: "Other workflow safety agency", slug: "other-workflow-safety-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Workflow safety manager", email: "workflow-safety@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:board) { organization.default_board }

  before { sign_in manager }

  def workflow_attributes(name:, action_configuration:)
    {
      name:, trigger_key: "order_approved", enabled: true,
      status_mappings_attributes: BoardWorkflow.default_status_mapping_attributes(board),
      actions_attributes: [
        { action_type: "place_on_board", configuration: action_configuration, position: 0 }
      ]
    }
  end

  it "rejects a workflow action that targets another organization's board before saving" do
    foreign_board = other_organization.default_board

    expect {
      post "/api/v1/boards/#{board.id}/workflows", params: {
        board_workflow: workflow_attributes(
          name: "Foreign placement",
          action_configuration: { board_id: foreign_board.id, column_key: "todo" }
        )
      }
    }.not_to change(BoardWorkflow, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("target board must belong to the workflow organization")
  end

  it "rejects a workflow action that points at a deleted or unknown board" do
    post "/api/v1/boards/#{board.id}/workflows", params: {
      board_workflow: workflow_attributes(
        name: "Missing placement",
        action_configuration: { board_id: 999_999, column_key: "todo" }
      )
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("target board must belong to the workflow organization")
    expect(BoardWorkflow.find_by(name: "Missing placement")).to be_nil
  end

  it "allows a valid shared-board target in the same organization" do
    shared_board = organization.boards.create!(name: "Shared workflow board", kind: :internal,
                                               visibility: :organization, requires_listing: false,
                                               client_visible: false, position: 1)
    WorkflowColumn::DEFAULTS.each { |attributes| shared_board.workflow_columns.create!(attributes.merge(organization:)) }

    post "/api/v1/boards/#{board.id}/workflows", params: {
      board_workflow: workflow_attributes(
        name: "Shared placement",
        action_configuration: { board_id: shared_board.id, column_key: "in_progress" }
      )
    }

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig("board_workflow", "actions").sole.fetch("configuration")).to include(
      "board_id" => shared_board.id.to_s, "column_key" => "in_progress"
    )
  end

  it "rejects assignment actions that target another organization's user or group" do
    foreign_user = User.create!(organization: other_organization, name: "Foreign assignment user",
                                email: "foreign-assignment-user@example.test", password: "long-enough-password",
                                role: :production_staff)
    foreign_group = other_organization.user_groups.create!(name: "Foreign assignment group")

    [
      { action_type: "assign_to_user", configuration: { user_id: foreign_user.id } },
      { action_type: "assign_to_group", configuration: { user_group_id: foreign_group.id } }
    ].each_with_index do |action, index|
      expect {
        post "/api/v1/boards/#{board.id}/workflows", params: {
          board_workflow: workflow_attributes(name: "Foreign assignment #{index}", action_configuration: action[:configuration]).merge(
            actions_attributes: [ action.merge(position: 0) ]
          )
        }
      }.not_to change(BoardWorkflow, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("target #{action[:action_type] == 'assign_to_user' ? 'user' : 'group'} must belong")
    end
  end
end
