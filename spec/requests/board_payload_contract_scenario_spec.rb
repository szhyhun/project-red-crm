require "rails_helper"

RSpec.describe "Board payload contract", type: :request do
  let!(:organization) { Organization.create!(name: "Board payload agency", slug: "board-payload-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Board payload manager", email: "board-payload-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:staff) do
    User.create!(organization:, name: "Board payload staff", email: "board-payload-staff@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:home_board) { organization.default_board }
  let!(:restricted_board) do
    organization.boards.create!(name: "Private review", kind: :internal, visibility: :restricted,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
      board.board_memberships.create!(member: manager, access: :manager)
    end
  end

  before { sign_in manager }

  it "returns ordered columns with every board so workflow targets are selectable" do
    get "/api/v1/boards"

    expect(response).to have_http_status(:ok)
    serialized = response.parsed_body.fetch("boards")
    home = serialized.find { |board| board.fetch("id") == home_board.id }
    private_board = serialized.find { |board| board.fetch("id") == restricted_board.id }

    expect(home.fetch("workflow_columns").map { |column| column.fetch("key") }).to eq(%w[todo in_progress blocked done])
    expect(private_board.fetch("workflow_columns").map { |column| column.fetch("board_id") }).to all(eq(restricted_board.id))
    expect(private_board.fetch("workflow_columns").map { |column| column.fetch("position") }).to eq([ 0, 1, 2, 3 ])
  end

  it "keeps board membership details off the collection while exposing them on show" do
    get "/api/v1/boards/#{restricted_board.id}"

    expect(response).to have_http_status(:ok)
    board = response.parsed_body.fetch("board")
    expect(board.fetch("workflow_columns").size).to eq(4)
    expect(board.fetch("members")).to include(
      include("member_id" => manager.id, "access" => "manager", "name" => manager.name)
    )

    get "/api/v1/boards"
    collection_board = response.parsed_body.fetch("boards").find { |entry| entry.fetch("id") == restricted_board.id }
    expect(collection_board).not_to have_key("members")
  end

  it "does not return a restricted board or its columns to an ungranted staff member" do
    sign_out manager
    sign_in staff

    get "/api/v1/boards"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("boards").map { |board| board.fetch("id") }).not_to include(restricted_board.id)

    get "/api/v1/boards/#{restricted_board.id}"
    expect(response).to have_http_status(:not_found)
  end
end
