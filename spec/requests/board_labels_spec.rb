require "rails_helper"

RSpec.describe "Board labels", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-board-labels") }
  let!(:manager) { staff("label-manager@example.test", :manager) }
  let!(:contributor) { staff("label-contributor@example.test", :production_staff) }
  let!(:outsider) { staff("label-outsider@example.test", :production_staff) }
  let!(:board) do
    organization.boards.create!(name: "Engineering", kind: "internal", visibility: "restricted",
                                requires_listing: false, client_visible: false, position: 1).tap do |created|
      WorkflowColumn::DEFAULTS.each { |attributes| created.workflow_columns.create!(attributes.merge(organization:)) }
      created.board_memberships.create!(member: manager, access: "manager")
      created.board_memberships.create!(member: contributor, access: "contributor")
    end
  end
  let!(:other_board) do
    organization.boards.create!(name: "Production", kind: "custom", visibility: "organization",
                                requires_listing: false, client_visible: false, position: 2).tap do |created|
      WorkflowColumn::DEFAULTS.each { |attributes| created.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end

  def staff(email, role)
    User.create!(organization:, name: email.split("@").first, email:,
                 password: "long-enough-password", role:)
  end

  it "keeps a restricted board's labels out of the hands of an ungranted user" do
    sign_in outsider

    get "/api/v1/boards/#{board.id}/labels"

    expect(response).to have_http_status(:not_found)
  end

  it "does not let a contributor change the board's shared label set" do
    sign_in contributor

    post "/api/v1/boards/#{board.id}/labels", params: { label: { name: "backend", color: "#e8f0ff" } }

    expect(response).to have_http_status(:forbidden)
    expect(board.board_labels).to be_empty
  end

  it "creates and returns labels owned by the board" do
    sign_in manager

    post "/api/v1/boards/#{board.id}/labels", params: { label: { name: "Backend", color: "#e8f0ff" } }

    expect(response).to have_http_status(:created)
    label = JSON.parse(response.body).fetch("label")
    expect(label).to include("board_id" => board.id, "name" => "Backend", "color" => "#e8f0ff", "task_count" => 0)
    expect(label.fetch("capabilities")).to include("manage")
  end

  it "keeps the same label name separate on different boards" do
    first = board.board_labels.create!(name: "backend", color: "#e8f0ff")
    second = other_board.board_labels.create!(name: "backend", color: "#fde7e3")

    expect(first.id).not_to eq(second.id)
    expect(first.board_id).to eq(board.id)
    expect(second.board_id).to eq(other_board.id)
  end

  it "rejects a task label that belongs to another board" do
    foreign_label = other_board.board_labels.create!(name: "production-only")
    task = board.workflow_tasks.create!(organization:, title: "Keep labels scoped", status: "todo")

    sign_in manager
    patch "/api/v1/workflow_tasks/#{task.id}",
          params: { workflow_task: { label_ids: [ foreign_label.id ] } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body).dig("details", "labels")).to include("must belong to this board")
    expect(task.reload.board_labels).to be_empty
  end

  it "assigns only labels already configured on the task's board" do
    label = board.board_labels.create!(name: "backend", color: "#e8f0ff")
    task = board.workflow_tasks.create!(organization:, title: "Use shared labels", status: "todo")

    sign_in manager
    patch "/api/v1/workflow_tasks/#{task.id}",
          params: { workflow_task: { label_ids: [ label.id ] } }

    expect(response).to have_http_status(:ok)
    expect(task.reload.board_labels).to contain_exactly(label)
    expect(JSON.parse(response.body).dig("workflow_task", "labels").first).to include(
      "id" => label.id, "name" => "backend", "board_id" => board.id
    )
  end

  it "allows a board manager to rename and delete a label" do
    label = board.board_labels.create!(name: "backend")
    sign_in manager

    patch "/api/v1/boards/#{board.id}/labels/#{label.id}", params: { label: { name: "api" } }

    expect(response).to have_http_status(:ok)
    expect(label.reload.name).to eq("api")

    delete "/api/v1/boards/#{board.id}/labels/#{label.id}"

    expect(response).to have_http_status(:no_content)
    expect(BoardLabel.exists?(label.id)).to be(false)
  end
end
