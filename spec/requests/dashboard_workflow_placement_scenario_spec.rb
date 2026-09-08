require "rails_helper"

RSpec.describe "Dashboard workflow placement scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Dashboard placement agency", slug: "dashboard-placement-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Dashboard placement manager", email: "dashboard-placement-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Dashboard placement client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "100 Dashboard Placement Street") }
  let!(:home_board) { organization.default_board }
  let!(:secondary_board) do
    organization.boards.create!(name: "Dashboard secondary", kind: :internal, visibility: :organization,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:shared_task) do
    home_board.workflow_tasks.create!(organization:, listing:, title: "Shared dashboard task", status: "todo", assignee: manager)
  end
  let!(:secondary_placement) do
    shared_task.workflow_task_placements.create!(
      board: secondary_board,
      workflow_column: secondary_board.workflow_columns.find_by!(key: "in_progress"),
      position: 0,
      is_home: false
    )
  end

  before { sign_in manager }

  it "counts a task from its canonical state after it is moved through a shared placement" do
    patch "/api/v1/workflow_tasks/#{shared_task.id}", params: {
      workflow_task: { board_id: secondary_board.id, status: "done", position: 0 }
    }
    expect(response).to have_http_status(:ok)

    get "/api/v1/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("tasks")).to include("mine" => 0, "blocked" => 0)
  end

  it "counts active assigned work and blocked work independently" do
    active_task = home_board.workflow_tasks.create!(organization:, listing:, title: "Active dashboard task",
                                                    status: "in_progress", assignee: manager)
    blocked_task = home_board.workflow_tasks.create!(organization:, listing:, title: "Blocked dashboard task",
                                                     status: "blocked", assignee: manager)

    get "/api/v1/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("tasks")).to include("mine" => 3, "blocked" => 1)
    expect([ active_task, blocked_task ]).to all(be_persisted)
  end
end
