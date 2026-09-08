require "rails_helper"

RSpec.describe Workflows::Runner do
  let!(:organization) { Organization.create!(name: "Runner edge agency", slug: "runner-edge-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Runner edge manager", email: "runner-edge-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Runner edge client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "3 Runner Edge Street") }
  let!(:service) do
    organization.products.create!(slug: "runner-edge-service", title: "Runner edge photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 1)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 15_000) }
  let!(:order) do
    order = Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                          status: :approved, approved_at: Time.current)
    order.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                              unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
    order
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }
  let!(:workflow) do
    organization.default_board.board_workflows.create!(organization:, name: "Edge workflow",
                                                        trigger_key: "order_approved", enabled: false,
                                                        created_by: manager)
  end
  let!(:run) do
    workflow.runs.create!(organization:, order:, idempotency_key: "runner-edge-#{SecureRandom.uuid}",
                          triggered_at: Time.current)
  end

  def add_action(type, configuration = {}, position: workflow.actions.maximum(:position).to_i + 1)
    workflow.actions.create!(action_type: type, configuration:, position:)
  end

  it "records an actionable warning when a configured user is suspended" do
    suspended_user = User.create!(organization:, name: "Suspended", email: "runner-edge-suspended@example.test",
                                  password: "long-enough-password", role: :production_staff, status: :suspended)
    add_action("create_or_group_child_task", {}, position: 0)
    add_action("assign_to_user", { "user_id" => suspended_user.id }, position: 1)

    described_class.new(run:).call

    expect(run.reload).to be_succeeded_with_warnings
    expect(run.error).to include("active organization user")
    expect(run.steps.order(:position).last).to have_attributes(status: "skipped")
    expect(WorkflowTask.where(organization:, assignee: manager)).to be_empty
  end

  it "records an actionable warning when a configured group is missing" do
    add_action("create_or_group_child_task", {}, position: 0)
    workflow.actions.build(action_type: "assign_to_group", configuration: { "user_group_id" => 999_999 }, position: 1)
      .save!(validate: false)

    described_class.new(run:).call

    expect(run.reload).to be_succeeded_with_warnings
    expect(run.error).to include("not in this organization")
    expect(run.steps.order(:position).last).to be_skipped
  end

  it "falls back to the first column when a board placement omits a valid column" do
    add_action("create_or_group_child_task", {}, position: 0)
    workflow.actions.build(action_type: "place_on_board",
                           configuration: { "board_id" => organization.default_board.id,
                                            "column_key" => "does_not_exist" }, position: 1).save!(validate: false)

    described_class.new(run:).call

    task = WorkflowTask.where(workflow_group_key: "deliverable:#{deliverable.materialization_key}").sole
    expect(task.home_placement.workflow_column).to eq(organization.default_board.workflow_columns.ordered.first)
    expect(run.reload).to be_succeeded
  end

  it "does not create work for a cancelled deliverable" do
    deliverable.update!(cancelled_at: Time.current)
    add_action("create_or_group_child_task", {}, position: 0)

    expect { described_class.new(run:).call }.not_to change(WorkflowTask, :count)

    expect(run.reload).to be_succeeded
    expect(run.steps.sole.output).to include("task_ids" => [], "deliverable_ids" => [])
  end

  it "skips deliverable task creation when the board requires a listing" do
    order_without_listing = Order.create!(organization:, client_account:, payment_mode: :pay_later,
                                          status: :approved, approved_at: Time.current)
    item = order_without_listing.order_items.create!(
      product: service,
      product_variant: variant,
      title: service.title,
      quantity: 1,
      unit_price_cents: variant.price_cents,
      total_cents: variant.price_cents,
      snapshot: OrderItem.catalog_snapshot(variant)
    )
    deliverable_without_listing = order_without_listing.order_deliverables.create!(
      organization:,
      order_item: item,
      service_product: service,
      title: service.title,
      deliverable_type: service.deliverable_type,
      sla_days: service.sla_days,
      materialization_key: "runner-edge-no-listing",
      position: 0
    )
    workflow_without_listing = organization.default_board.board_workflows.create!(
      organization:,
      name: "Required listing workflow",
      trigger_key: "order_approved",
      enabled: false,
      created_by: manager
    )
    workflow_without_listing.actions.create!(action_type: :create_or_group_child_task, configuration: {}, position: 0)
    run_without_listing = workflow_without_listing.runs.create!(
      organization:,
      order: order_without_listing,
      idempotency_key: "runner-edge-no-listing-#{SecureRandom.uuid}",
      triggered_at: Time.current
    )

    expect do
      described_class.new(run: run_without_listing).call
    end.not_to change(WorkflowTask, :count)

    expect(run_without_listing.reload).to be_succeeded_with_warnings
    expect(run_without_listing.error).to include("No listing is available for deliverable tasks")
    expect(deliverable_without_listing.reload.workflow_tasks).to be_empty
  end
end
