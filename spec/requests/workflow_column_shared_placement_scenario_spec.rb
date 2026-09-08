require "rails_helper"

RSpec.describe "Workflow column shared placement scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Column placement agency", slug: "column-placement-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Column placement manager", email: "column-placement-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Column placement client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "90 Column Placement Street") }
  let!(:home_board) { organization.default_board }
  let!(:secondary_board) do
    organization.boards.create!(name: "Secondary placement board", kind: :internal, visibility: :organization,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:home_column) do
    home_board.workflow_columns.create!(organization:, name: "Quality check", color: "#aec7f7", category: :active, position: 4)
  end
  let!(:task) do
    home_board.workflow_tasks.create!(organization:, listing:, title: "Delete-safe shared task", status: home_column.key)
  end
  let!(:secondary_placement) do
    task.workflow_task_placements.create!(
      board: secondary_board,
      workflow_column: secondary_board.workflow_columns.find_by!(key: "todo"),
      position: 0,
      is_home: false
    )
  end

  before { sign_in manager }

  it "moves every board placement to the replacement state before deleting a used column" do
    delete "/api/v1/boards/#{home_board.id}/workflow_columns/#{home_column.id}", params: {
      replacement_column_id: home_board.workflow_columns.find_by!(key: "done").id
    }

    expect(response).to have_http_status(:no_content)
    expect(task.reload).to have_attributes(status: "done", completed_at: be_present)
    expect(task.workflow_task_placements.find_by!(board: home_board).workflow_column.key).to eq("done")
    expect(task.workflow_task_placements.find_by!(board: secondary_board).workflow_column.key).to eq("done")
    expect(WorkflowColumn.exists?(home_column.id)).to be(false)
  end

  it "does not delete a used column when no replacement is supplied" do
    delete "/api/v1/boards/#{home_board.id}/workflow_columns/#{home_column.id}"

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("details").fetch("base").join).to include("Choose a replacement column")
    expect(WorkflowColumn.exists?(home_column.id)).to be(true)
    expect(task.reload.status).to eq(home_column.key)
    expect(task.workflow_task_placements.find_by!(board: secondary_board).workflow_column.key).to eq("todo")
  end

  it "updates the canonical task when only a secondary placement uses the deleted column" do
    secondary_todo = secondary_board.workflow_columns.find_by!(key: "todo")
    secondary_done = secondary_board.workflow_columns.find_by!(key: "done")

    delete "/api/v1/boards/#{secondary_board.id}/workflow_columns/#{secondary_todo.id}", params: {
      replacement_column_id: secondary_done.id
    }

    expect(response).to have_http_status(:no_content)
    expect(task.reload).to have_attributes(status: "done", completed_at: be_present)
    expect(task.workflow_task_placements.find_by!(board: home_board).workflow_column.key).to eq("done")
    expect(task.workflow_task_placements.find_by!(board: secondary_board).workflow_column.key).to eq("done")
    expect(WorkflowColumn.exists?(secondary_todo.id)).to be(false)
  end
end
