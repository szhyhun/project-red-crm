require "rails_helper"

RSpec.describe WorkflowColumn, type: :model do
  let!(:organization) { Organization.create!(name: "Column mapping agency", slug: "column-mapping-agency") }
  let!(:board) { organization.default_board }

  def add_column(key:, name:, category:, position:)
    board.workflow_columns.create!(organization:, key:, name:, color: "#c9b6ff", category:, position:)
  end

  it "maps the default board columns to the customer-facing states" do
    expect(board.workflow_columns.find_by!(key: "todo").canonical_status).to eq("not_started")
    expect(board.workflow_columns.find_by!(key: "in_progress").canonical_status).to eq("in_progress")
    expect(board.workflow_columns.find_by!(key: "blocked").canonical_status).to eq("in_progress")
    expect(board.workflow_columns.find_by!(key: "done").canonical_status).to eq("delivered")
  end

  it "recognizes review-like column keys as the review state" do
    review = add_column(key: "review", name: "Review", category: :active, position: 4)
    qa = add_column(key: "quality_assurance", name: "Quality assurance", category: :active, position: 5)
    approval = add_column(key: "approval", name: "Approval", category: :active, position: 6)

    expect([ review, qa, approval ].map(&:canonical_status)).to all(eq("in_review"))
  end

  it "prioritizes completed and blocked categories over their names" do
    archived = add_column(key: "archived", name: "Archived", category: :completed, position: 4)
    blocked = add_column(key: "waiting_on_client", name: "Waiting on client", category: :blocked, position: 5)

    expect(archived.canonical_status).to eq("delivered")
    expect(blocked.canonical_status).to eq("in_progress")
  end

  it "uses a custom review column when generating default workflow mappings" do
    add_column(key: "review", name: "Review", category: :active, position: 4)

    mappings = BoardWorkflow.default_status_mapping_attributes(board)
      .index_by { |mapping| mapping.fetch(:source_status) }

    expect(mappings.fetch("not_started").fetch(:target_column_key)).to eq("todo")
    expect(mappings.fetch("in_progress").fetch(:target_column_key)).to eq("in_progress")
    expect(mappings.fetch("in_review").fetch(:target_column_key)).to eq("review")
    expect(mappings.fetch("delivered").fetch(:target_column_key)).to eq("done")
  end

  it "falls back to active work when a board has no dedicated review column" do
    mappings = BoardWorkflow.default_status_mapping_attributes(board)
      .index_by { |mapping| mapping.fetch(:source_status) }

    expect(mappings.fetch("in_review").fetch(:target_column_key)).to eq("in_progress")
  end
end
