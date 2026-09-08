require "rails_helper"

RSpec.describe "Workflow task move authorization API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Move authorization agency", slug: "move-authorization-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Move authorization manager", email: "move-authorization-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:viewer) do
    User.create!(organization:, name: "Move authorization viewer", email: "move-authorization-viewer@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:contributor) do
    User.create!(organization:, name: "Move authorization contributor", email: "move-authorization-contributor@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Move authorization client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "4 Move Authorization Street") }
  let!(:home_board) { organization.default_board }
  let!(:shared_board) do
    organization.boards.create!(name: "Move authorization review", kind: :internal, visibility: :restricted,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:task) do
    home_board.workflow_tasks.create!(organization:, listing:, title: "Move the delivered photos", status: "todo")
  end
  let!(:shared_placement) do
    task.workflow_task_placements.create!(board: shared_board,
                                          workflow_column: shared_board.workflow_columns.find_by!(key: "todo"),
                                          position: 0)
  end

  before do
    shared_board.board_memberships.create!(member: viewer, access: :viewer)
    shared_board.board_memberships.create!(member: contributor, access: :contributor)
  end

  it "allows a viewer to read a shared placement but rejects a move" do
    sign_in viewer

    get "/api/v1/boards/#{shared_board.id}/workflow_tasks"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("workflow_tasks")).to include(include("id" => task.id))

    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { board_id: shared_board.id, status: "done", position: 0 }
    }

    expect(response).to have_http_status(:forbidden)
    expect(task.reload.status).to eq("todo")
    expect(shared_placement.reload.workflow_column.key).to eq("todo")
  end

  it "allows a contributor to move the shared placement and synchronizes the home card" do
    sign_in contributor

    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { board_id: shared_board.id, status: "done", position: 0 }
    }

    expect(response).to have_http_status(:ok)
    expect(task.reload).to have_attributes(status: "done", completed_at: be_present)
    expect(task.home_placement.workflow_column.key).to eq("done")
    expect(shared_placement.reload.workflow_column.key).to eq("done")
  end
end
