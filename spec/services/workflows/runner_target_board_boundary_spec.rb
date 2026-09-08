require "rails_helper"

RSpec.describe Workflows::Runner do
  let!(:organization) { Organization.create!(name: "Target board agency", slug: "target-board-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Target board manager", email: "target-board-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Target board client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "1 Target Board Street") }
  let!(:production_board) { organization.default_board }
  let!(:internal_board) do
    organization.boards.create!(name: "Internal operations", kind: :internal, visibility: :organization,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:service) do
    organization.products.create!(slug: "target-board-service", title: "Target board photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:workflow) do
    internal_board.board_workflows.create!(organization:, name: "Target board workflow", trigger_key: "order_approved",
                                           enabled: false, created_by: manager)
  end

  def build_run(listing: self.listing)
    order = Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                          status: :approved, approved_at: Time.current)
    item = order.order_items.create!(product: service, product_variant: variant, title: service.title,
                                     quantity: 1, unit_price_cents: variant.price_cents, total_cents: variant.price_cents,
                                     snapshot: OrderItem.catalog_snapshot(variant))
    Orders::DeliverableMaterializer.new(order:).call
    workflow.runs.create!(organization:, order:, idempotency_key: "target-board-#{SecureRandom.uuid}",
                          triggered_at: Time.current).tap do |run|
      expect(item).to be_persisted
    end
  end

  it "records a warning instead of failing when a listingless task targets a listing board" do
    run = build_run(listing: nil)
    workflow.actions.create!(action_type: "create_or_group_child_task", configuration: { "customer_visible" => false }, position: 0)
    workflow.actions.create!(action_type: "place_on_board",
                             configuration: { "board_id" => production_board.id, "column_key" => "todo" }, position: 1)

    expect { described_class.new(run:).call }.not_to raise_error

    expect(run.reload).to be_succeeded_with_warnings
    expect(run.error).to include("No listing is available for the target board")
    expect(run.steps.order(:position).last).to have_attributes(status: "skipped")
    expect(WorkflowTask.where(organization:, workflow_group_key: "deliverable:#{run.order.order_deliverables.sole.materialization_key}")
      .sole.workflow_task_placements.where(board: production_board)).to be_empty
  end

  it "creates a placement when the target board's listing requirement is satisfied" do
    run = build_run
    workflow.actions.create!(action_type: "create_or_group_child_task", configuration: { "customer_visible" => false }, position: 0)
    workflow.actions.create!(action_type: "place_on_board",
                             configuration: { "board_id" => production_board.id, "column_key" => "in_progress" }, position: 1)

    described_class.new(run:).call

    task = WorkflowTask.where(organization:, task_kind: "deliverable").sole
    expect(run.reload).to be_succeeded
    expect(task.workflow_task_placements.find_by!(board: production_board)).to have_attributes(
      workflow_column: production_board.workflow_columns.find_by!(key: "in_progress"), is_home: false
    )
  end

  it "keeps a task on its home board when the workflow has no target column" do
    target_board = organization.boards.create!(name: "Empty target", kind: :internal, visibility: :organization,
                                               requires_listing: false, client_visible: false, position: 2)
    run = build_run
    workflow.actions.create!(action_type: "create_or_group_child_task", configuration: { "customer_visible" => false }, position: 0)
    workflow.actions.create!(action_type: "place_on_board", configuration: { "board_id" => target_board.id }, position: 1)

    described_class.new(run:).call

    task = WorkflowTask.where(organization:, task_kind: "deliverable").sole
    expect(run.reload).to be_succeeded_with_warnings
    expect(run.error).to include("workflow has no target column")
    expect(task.workflow_task_placements.where(board: target_board)).to be_empty
    expect(task.home_placement.board).to eq(internal_board)
  end
end
