require "rails_helper"

RSpec.describe WorkflowTaskPolicy do
  let!(:organization) { Organization.create!(name: "Task policy agency", slug: "task-policy-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Board manager", email: "task-policy-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:viewer) do
    User.create!(organization:, name: "Board viewer", email: "task-policy-viewer@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:assignee) do
    User.create!(organization:, name: "Assigned producer", email: "task-policy-assignee@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:outsider) do
    User.create!(organization:, name: "Board outsider", email: "task-policy-outsider@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Policy client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "1 Policy Street") }
  let!(:home_board) { organization.default_board }
  let!(:shared_board) do
    organization.boards.create!(name: "Review board", kind: :internal, visibility: :restricted,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:task) do
    home_board.workflow_tasks.create!(organization:, listing:, title: "Review shared work", status: "todo")
  end
  let!(:shared_placement) do
    task.workflow_task_placements.create!(board: shared_board,
                                          workflow_column: shared_board.workflow_columns.find_by!(key: "todo"),
                                          position: 0)
  end

  before do
    home_board.update!(visibility: :restricted)
    shared_board.board_memberships.create!(member: viewer, access: :viewer)
  end

  it "allows viewing a task through an authorized secondary placement" do
    policy = described_class.new(viewer, task)

    expect(policy.view?).to be(true)
    expect(shared_placement.board_id).to eq(shared_board.id)
  end

  it "hides a task when the user cannot see either its home board or placements" do
    policy = described_class.new(outsider, task)

    expect(policy.view?).to be(false)
    expect(policy.update?).to be(false)
  end

  it "scopes in tasks visible only through a secondary placement" do
    private_task = home_board.workflow_tasks.create!(organization:, listing:, title: "Private home task", status: "todo")
    resolved = described_class::Scope.new(viewer, WorkflowTask).resolve

    expect(resolved).to include(task)
    expect(resolved).not_to include(private_task)
  end

  it "does not let a viewer move an unassigned task through a shared board" do
    policy = described_class.new(viewer, task)

    expect(policy.update_on_board?(shared_board)).to be(false)
    expect(policy.update?).to be(false)
  end

  it "lets a contributor move a task through its shared placement" do
    shared_board.board_memberships.find_by!(member: viewer).update!(access: :contributor)
    policy = described_class.new(viewer, task)

    expect(policy.update_on_board?(shared_board)).to be(true)
    expect(policy.update?).to be(true)
  end

  it "lets the assignee move their own task with viewer access" do
    home_board.board_memberships.create!(member: assignee, access: :viewer)
    task.update!(assignee: assignee)
    policy = described_class.new(assignee, task)

    expect(policy.update_on_board?(home_board)).to be(true)
    expect(policy.update?).to be(true)
  end
end
