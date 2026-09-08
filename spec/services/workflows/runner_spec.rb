require "rails_helper"

RSpec.describe Workflows::Runner do
  let!(:organization) { Organization.create!(name: "Runner Agency", slug: "runner-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Workflow Manager", email: "runner-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Runner Client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "1 Runner Street") }
  let!(:board) { organization.default_board }
  let!(:service) do
    Product.create!(organization:, slug: "runner-photography", title: "Photography", kind: :service,
                    deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) do
    service.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 29_900, sqft_min: 0, sqft_max: 1_000)
  end
  let!(:order) do
    Orders::Creator.new(
      organization:,
      attributes: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: variant.id, quantity: 1 } ]
      }
    ).create!
  end
  let!(:workflow) do
    board.board_workflows.create!(organization:, name: "Runner workflow", trigger_key: "order_approved",
                                  created_by: manager, enabled: false)
  end
  let!(:run) do
    BoardWorkflowRun.create!(organization:, board_workflow: workflow, order:,
                             idempotency_key: "runner-#{SecureRandom.uuid}", triggered_at: Time.current)
  end

  before do
    order.update!(status: :approved, approved_at: Time.current)
    Orders::DeliverableMaterializer.new(order:).call
  end

  def add_action(type, configuration = {}, position: workflow.actions.maximum(:position).to_i + 1)
    workflow.actions.create!(action_type: type, configuration:, position:)
  end

  it "creates one parent task, one deliverable task, and the home placement" do
    add_action("create_parent_task", { "title" => "Production" }, position: 0)
    add_action("create_or_group_child_task", { "customer_visible" => true }, position: 1)

    expect {
      described_class.new(run:).call
    }.to change(WorkflowTask, :count).by(2)
      .and change(WorkflowTaskPlacement, :count).by(2)
      .and change(WorkflowTaskDeliverable, :count).by(1)

    parent, child = WorkflowTask.order(:id).last(2)
    expect(parent).to have_attributes(task_kind: "parent", listing_id: listing.id, parent_task_id: nil)
    expect(child).to have_attributes(task_kind: "deliverable", listing_id: listing.id,
                                     parent_task_id: parent.id, customer_visible: true, status: "todo")
    expect(child.home_placement).to have_attributes(board_id: board.id, is_home: true)
    expect(child.order_deliverables).to contain_exactly(order.reload.order_deliverables.sole)
    expect(run.reload).to be_succeeded
  end

  it "uses the workflow status mapping for the initial deliverable task column" do
    workflow.status_mappings.create!(source_status: "not_started", target_column_key: "in_progress", position: 0)
    add_action("create_or_group_child_task", { "customer_visible" => true }, position: 0)

    described_class.new(run:).call

    task = WorkflowTask.where(task_kind: "deliverable").sole
    expect(task).to have_attributes(status: "in_progress")
    expect(task.home_placement.workflow_column.key).to eq("in_progress")
  end

  it "is idempotent when the same successful run is delivered twice" do
    add_action("create_parent_task", { "title" => "Production" }, position: 0)
    add_action("create_or_group_child_task", {}, position: 1)

    described_class.new(run:).call
    counts = [ WorkflowTask.count, WorkflowTaskPlacement.count, WorkflowTaskDeliverable.count, run.steps.count ]

    described_class.new(run: run.reload).call

    expect([ WorkflowTask.count, WorkflowTaskPlacement.count, WorkflowTaskDeliverable.count, run.reload.steps.count ]).to eq(counts)
    expect(WorkflowTask.where(workflow_group_key: "deliverable:#{order.order_deliverables.sole.materialization_key}").count).to eq(1)
  end

  it "filters deliverables through workflow conditions" do
    workflow.conditions.create!(field: "deliverable_type", operator: "equals", value: "video", position: 0)
    add_action("create_or_group_child_task", {}, position: 0)

    described_class.new(run:).call

    expect(run.reload).to be_succeeded
    expect(run.steps.sole).to be_succeeded
    expect(WorkflowTask.where("workflow_group_key LIKE ?", "deliverable:%")).to be_empty
  end

  it "places shared tasks on a second board without changing their home board" do
    second_board = organization.boards.create!(name: "Client Delivery", kind: :internal,
                                                 visibility: :organization, requires_listing: false,
                                                 client_visible: false, position: 1)
    WorkflowColumn::DEFAULTS.each { |attributes| second_board.workflow_columns.create!(attributes.merge(organization:)) }
    add_action("create_or_group_child_task", {}, position: 0)
    add_action("place_on_board", { "board_id" => second_board.id, "column_key" => "in_progress" }, position: 1)

    described_class.new(run:).call

    task = WorkflowTask.where(task_kind: "deliverable").sole
    expect(task.home_placement).to have_attributes(board_id: board.id, is_home: true)
    expect(task.workflow_task_placements.find_by(board: second_board)).to have_attributes(
      workflow_column: second_board.workflow_columns.find_by!(key: "in_progress"), is_home: false
    )
  end

  it "assigns matching tasks to a user and group configured by the workflow" do
    group = organization.user_groups.create!(name: "Editors")
    add_action("create_or_group_child_task", {}, position: 0)
    add_action("assign_to_user", { "user_id" => manager.id }, position: 1)
    add_action("assign_to_group", { "user_group_id" => group.id }, position: 2)

    described_class.new(run:).call

    task = WorkflowTask.where(task_kind: "deliverable").sole
    expect(task.assignee).to eq(manager)
    expect(task.metadata).to include("assigned_group_id" => group.id)
  end

  it "records unsupported actions as warnings instead of claiming they ran" do
    action = add_action("link_deliverable", {}, position: 0)
    action.update_column(:action_type, "future_action")

    described_class.new(run:).call

    expect(run.reload).to be_succeeded_with_warnings
    expect(run.error).to include("Unsupported workflow action future_action")
    expect(run.steps.sole).to be_skipped
    expect(run.steps.sole.output).to include("warning" => "Unsupported workflow action future_action")
  end

  it "fails and records the step when an action targets another organization" do
    other_organization = Organization.create!(name: "Other Runner Agency", slug: "other-runner-agency")
    other_board = other_organization.default_board
    # Keep coverage for legacy rows that predate configuration validation.
    action = workflow.actions.build(action_type: "place_on_board",
                                    configuration: { "board_id" => other_board.id, "column_key" => "todo" }, position: 0)
    action.save!(validate: false)

    expect {
      described_class.new(run:).call
    }.to raise_error(ActiveRecord::RecordNotFound)

    expect(run.reload).to be_failed
    expect(run.error).to include("ActiveRecord::RecordNotFound")
    expect(run.steps.sole).to be_failed
    expect(run.steps.sole.error).to include("ActiveRecord::RecordNotFound")
  end
end
