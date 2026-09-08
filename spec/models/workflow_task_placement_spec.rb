require "rails_helper"

RSpec.describe WorkflowTaskPlacement, type: :model do
  let!(:organization) { Organization.create!(name: "Placement model agency", slug: "placement-model-agency") }
  let!(:other_organization) { Organization.create!(name: "Other placement model agency", slug: "other-placement-model-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Placement client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "2 Placement Street") }
  let!(:home_board) { organization.default_board }
  let!(:second_board) do
    organization.boards.create!(name: "Secondary board", kind: :internal, visibility: :organization,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:task) do
    home_board.workflow_tasks.create!(organization:, listing:, title: "Placement task", status: "todo", position: 0)
  end

  it "creates exactly one home placement when a task is created" do
    placement = task.workflow_task_placements.sole

    expect(placement).to have_attributes(board_id: home_board.id, is_home: true, position: 0)
    expect(placement.workflow_column.key).to eq("todo")
  end

  it "does not create another placement when the canonical task is edited" do
    expect { task.update!(title: "Renamed placement task", position: 3) }
      .not_to change(WorkflowTaskPlacement, :count)

    expect(task.reload.workflow_task_placements.where(is_home: true).count).to eq(1)
    expect(task.home_placement.position).to eq(0)
  end

  it "rejects a placement whose column belongs to another board" do
    invalid = task.workflow_task_placements.build(
      board: second_board,
      workflow_column: home_board.workflow_columns.find_by!(key: "todo"),
      position: 0
    )

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include("Workflow column must belong to the selected board")
  end

  it "rejects a placement that crosses organization boundaries" do
    foreign_board = other_organization.default_board
    invalid = task.workflow_task_placements.build(
      board: foreign_board,
      workflow_column: foreign_board.workflow_columns.find_by!(key: "todo"),
      position: 0
    )

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include("task and board must belong to the same organization")
  end

  it "requires a listing when placing a task on a listing-required board" do
    listing_required_board = organization.boards.create!(name: "Listing required", kind: :production,
                                                          visibility: :organization, requires_listing: true,
                                                          client_visible: true, position: 3).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
    listingless_task = second_board.workflow_tasks.create!(organization:, title: "Listing required work", status: "todo")
    invalid = listingless_task.workflow_task_placements.build(
      board: listing_required_board,
      workflow_column: listing_required_board.workflow_columns.find_by!(key: "todo"),
      position: 0
    )

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include("Workflow task must have a listing on this board")
  end

  it "allows one placement per board and rejects a duplicate at the database boundary" do
    task.workflow_task_placements.create!(
      board: second_board,
      workflow_column: second_board.workflow_columns.find_by!(key: "todo"),
      position: 0
    )
    duplicate = task.workflow_task_placements.build(
      board: second_board,
      workflow_column: second_board.workflow_columns.find_by!(key: "done"),
      position: 0
    )

    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "orders placements by board position before id" do
    later = task.workflow_task_placements.create!(
      board: second_board,
      workflow_column: second_board.workflow_columns.find_by!(key: "todo"),
      position: 4
    )
    earlier = task.workflow_task_placements.create!(
      board: organization.boards.create!(name: "Third board", kind: :internal, visibility: :organization,
                                          requires_listing: false, client_visible: false, position: 2).tap do |board|
        WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
      end,
      workflow_column: WorkflowColumn.last,
      position: 1
    )

    expect(task.workflow_task_placements.ordered.map(&:id)).to eq([ task.home_placement.id, earlier.id, later.id ])
  end
end
