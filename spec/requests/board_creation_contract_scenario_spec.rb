require "rails_helper"

RSpec.describe "Board creation contract API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Board creation agency", slug: "board-creation-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Board creation manager", email: "board-creation-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Board creation client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "70 Board Creation Street") }

  before { sign_in manager }

  it "creates a board with its own columns and preserves board-scoped task rules" do
    post "/api/v1/boards", params: {
      board: {
        name: "Internal operations",
        kind: "internal",
        visibility: "organization",
        requires_listing: false,
        client_visible: false
      }
    }

    expect(response).to have_http_status(:created)
    board = Board.find(response.parsed_body.dig("board", "id"))
    expect(board.workflow_columns.ordered.pluck(:key)).to eq(%w[todo in_progress blocked done])
    expect(response.parsed_body.dig("board", "requires_listing")).to be(false)

    post "/api/v1/boards/#{board.id}/workflow_tasks", params: {
      workflow_task: { title: "Review import mapping" }
    }

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig("workflow_task")).to include(
      "board_id" => board.id,
      "listing_id" => nil,
      "status" => "todo"
    )
  end

  it "requires a listing when a newly created board is configured for property work" do
    post "/api/v1/boards", params: {
      board: {
        name: "Property operations",
        kind: "production",
        visibility: "organization",
        requires_listing: true,
        client_visible: true
      }
    }

    expect(response).to have_http_status(:created)
    board = Board.find(response.parsed_body.dig("board", "id"))

    post "/api/v1/boards/#{board.id}/workflow_tasks", params: {
      workflow_task: { title: "Prepare property delivery" }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "listing")).to include("is required on this board")
  end

  it "does not expose a staff board to a customer even when the board is organization-visible" do
    post "/api/v1/boards", params: {
      board: {
        name: "Staff-only operations",
        kind: "internal",
        visibility: "organization",
        requires_listing: false,
        client_visible: false
      }
    }
    expect(response).to have_http_status(:created)
    board_id = response.parsed_body.dig("board", "id")

    client_user = User.create!(organization:, name: "Board creation customer", email: "board-creation-client@example.test",
                               password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account:, user: client_user, role: :admin)
    sign_out manager
    sign_in client_user

    get "/api/v1/boards/#{board_id}/workflow_tasks"

    expect(response).to have_http_status(:forbidden)
  end
end
