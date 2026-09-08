require "rails_helper"

RSpec.describe WorkflowTask, type: :model do
  let!(:organization) { Organization.create!(name: "Task board rules agency", slug: "task-board-rules-agency") }
  let!(:other_organization) { Organization.create!(name: "Other task board rules agency", slug: "other-task-board-rules-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Task board rules client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "1 Task Board Rules Street") }
  let!(:staff) do
    User.create!(organization:, name: "Task board rules producer", email: "task-board-rules-producer@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:foreign_staff) do
    User.create!(organization: other_organization, name: "Foreign producer", email: "foreign-task-board-rules@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:production_board) { organization.default_board }
  let!(:internal_board) do
    organization.boards.create!(name: "Internal work", kind: :internal, visibility: :organization,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:restricted_board) do
    organization.boards.create!(name: "Restricted work", kind: :internal, visibility: :restricted,
                                requires_listing: false, client_visible: false, position: 2).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end

  it "requires a listing for a task on a production board" do
    task = production_board.workflow_tasks.build(organization:, title: "Prepare listing photos", status: "todo")

    expect(task).not_to be_valid
    expect(task.errors.full_messages).to include("Listing is required on this board")
  end

  it "allows a listingless task on an internal board" do
    task = internal_board.workflow_tasks.build(organization:, title: "Update workflow documentation", status: "todo")

    expect(task).to be_valid
  end

  it "requires a customer-visible board for a customer-visible task" do
    task = internal_board.workflow_tasks.build(organization:, title: "Customer progress", status: "todo",
                                               customer_visible: true)

    expect(task).not_to be_valid
    expect(task.errors.full_messages).to include("Customer visible requires a customer-visible board")
  end

  it "requires the canonical task status to be a column on its board" do
    task = internal_board.workflow_tasks.build(organization:, title: "Use a real column", status: "not_a_column")

    expect(task).not_to be_valid
    expect(task.errors.full_messages).to include("Status must match a column on this board")
  end

  it "rejects an assignee without access to a restricted board" do
    task = restricted_board.workflow_tasks.build(organization:, title: "Private production task", status: "todo",
                                                 assignee: staff)

    expect(task).not_to be_valid
    expect(task.errors.full_messages).to include("Assignee must have access to this board")
  end

  it "accepts an assignee after that user is granted restricted-board access" do
    restricted_board.board_memberships.create!(member: staff, access: :contributor)
    task = restricted_board.workflow_tasks.build(organization:, title: "Assigned private task", status: "todo",
                                                 assignee: staff)

    expect(task).to be_valid
  end

  it "rejects an assignee from another organization even when the task board is internal" do
    task = internal_board.workflow_tasks.build(organization:, title: "Cross-tenant task", status: "todo",
                                               assignee: foreign_staff)

    expect(task).not_to be_valid
    expect(task.errors.full_messages).to include("Assignee must have access to this board")
  end
end
