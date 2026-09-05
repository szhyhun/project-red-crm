require "rails_helper"

RSpec.describe "Board tasks", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-board-tasks") }
  let!(:manager) do
    User.create!(organization:, name: "Morgan", email: "board-tasks@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account: client_account, address_line_1: "111 Oak Bay Avenue") }
  let!(:production_board) { organization.default_board }
  let!(:internal_board) do
    organization.boards.create!(name: "CRM Development", kind: "internal", visibility: "organization",
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end

  before { sign_in manager }

  it "creates a task with no listing on a board that does not require one" do
    post "/api/v1/boards/#{internal_board.id}/workflow_tasks", params: {
      workflow_task: { title: "Move workflow tasks onto boards", stage: "build", external_ref: "T2" }
    }

    expect(response).to have_http_status(:created)
    task = JSON.parse(response.body).fetch("workflow_task")
    expect(task).to include("listing_id" => nil, "board_id" => internal_board.id, "external_ref" => "T2")
  end

  it "still requires a listing on a production board" do
    post "/api/v1/boards/#{production_board.id}/workflow_tasks", params: {
      workflow_task: { title: "Edit hero video", stage: "editing" }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body).dig("details", "listing")).to include("is required on this board")
  end

  it "keeps identical column keys on separate boards apart" do
    task = internal_board.workflow_tasks.create!(organization:, title: "Ship boards", stage: "build", status: "todo")
    other = production_board.workflow_tasks.create!(organization:, listing:, title: "Edit", stage: "editing", status: "todo")

    get "/api/v1/boards/#{internal_board.id}/workflow_tasks"

    ids = JSON.parse(response.body).fetch("workflow_tasks").pluck("id")
    expect(ids).to contain_exactly(task.id)
    expect(ids).not_to include(other.id)
  end

  it "hides restricted-board tasks from the listing task feed" do
    restricted_board = organization.boards.create!(name: "Private Production", kind: "internal", visibility: "restricted",
                                                    requires_listing: true, client_visible: false, position: 2)
    WorkflowColumn::DEFAULTS.each { |attributes| restricted_board.workflow_columns.create!(attributes.merge(organization:)) }
    restricted_board.workflow_tasks.create!(organization:, listing:, title: "Private QA", stage: "review", status: "todo")
    production_board.workflow_tasks.create!(organization:, listing:, title: "Public QA", stage: "review", status: "todo")

    get "/api/v1/listings/#{listing.id}/workflow_tasks"

    titles = JSON.parse(response.body).fetch("workflow_tasks").pluck("title")
    expect(titles).to contain_exactly("Public QA")
  end

  # Creating from a listing predates boards. It has to keep working without a
  # board id, resolving to the organization's default board.
  it "still accepts a task created from a listing" do
    post "/api/v1/listings/#{listing.id}/workflow_tasks", params: {
      workflow_task: { title: "Colour grade", stage: "editing" }
    }

    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body).dig("workflow_task", "board_id")).to eq(production_board.id)
  end

  it "still serves columns unscoped for clients that predate boards" do
    get "/api/v1/workflow_columns"

    expect(response).to have_http_status(:ok)
    columns = JSON.parse(response.body).fetch("workflow_columns")
    expect(columns.pluck("key")).to eq(%w[todo in_progress blocked done])
    expect(columns.pluck("board_id").uniq).to eq([ production_board.id ])
  end

  # customer_visible alone is not enough: an internal board's tasks must never
  # reach a client even if someone flags one visible.
  it "withholds customer-visible tasks that live on a board clients cannot see" do
    client_user = User.create!(organization:, name: "Avery", email: "client-board@example.test",
                               password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account:, user: client_user)
    internal_board.update!(requires_listing: true)
    internal_board.workflow_tasks.create!(organization:, listing:, title: "Internal", stage: "build",
                                          status: "todo", customer_visible: true)
    production_board.workflow_tasks.create!(organization:, listing:, title: "Retouch", stage: "editing",
                                            status: "todo", customer_visible: true)

    sign_out manager
    sign_in client_user
    get "/api/v1/listings/#{listing.id}/workflow_tasks"

    titles = JSON.parse(response.body).fetch("workflow_tasks").pluck("title")
    expect(titles).to contain_exactly("Retouch")
  end
end
