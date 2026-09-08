require "rails_helper"

RSpec.describe "Shared board count API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Shared count agency", slug: "shared-count-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Shared count manager", email: "shared-count-manager@example.test",
                password: "long-enough-password", role: :manager)
  end
  let!(:listing) do
    client = ClientAccount.create!(organization:, name: "Shared count client", kind: :agent)
    Listing.create!(organization:, client_account: client, address_line_1: "27 Shared Count Road")
  end
  let!(:home_board) { organization.default_board }
  let!(:shared_board) do
    organization.boards.create!(
      name: "Shared count review",
      kind: :internal,
      visibility: :organization,
      requires_listing: false,
      client_visible: false,
      position: 1
    ).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:task) do
    home_board.workflow_tasks.create!(
      organization:,
      listing:,
      title: "Count the shared card",
      status: "todo"
    ).tap do |record|
      record.workflow_task_placements.create!(
        board: shared_board,
        workflow_column: shared_board.workflow_columns.find_by!(key: "todo"),
        position: 0
      )
    end
  end

  before { sign_in manager }

  it "counts placements on each board instead of only home-board task rows" do
    get "/api/v1/boards/#{home_board.id}"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("board", "task_count")).to eq(1)

    get "/api/v1/boards/#{shared_board.id}"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("board", "task_count")).to eq(1)
  end

  it "counts a shared placement in the selected column payload" do
    get "/api/v1/boards/#{shared_board.id}/workflow_columns"

    expect(response).to have_http_status(:ok)
    todo = response.parsed_body.fetch("workflow_columns").find { |column| column.fetch("key") == "todo" }
    expect(todo).to include("task_count" => 1)
  end
end
