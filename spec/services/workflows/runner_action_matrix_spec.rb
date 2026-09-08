require "rails_helper"

RSpec.describe Workflows::Runner do
  let!(:organization) { Organization.create!(name: "Action matrix agency", slug: "action-matrix-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Action matrix manager", email: "action-matrix-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Action matrix client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "30 Action Matrix Street") }
  let!(:board) { organization.default_board }
  let!(:secondary_board) do
    organization.boards.create!(name: "Delivery board", kind: :internal, visibility: :organization,
                                requires_listing: false, client_visible: false, position: 1).tap do |new_board|
      WorkflowColumn::DEFAULTS.each { |attributes| new_board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:service) do
    organization.products.create!(slug: "action-matrix-service", title: "Action matrix photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 12_000) }
  let!(:order) do
    Orders::Creator.new(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).create!
  end
  let!(:deliverable) do
    order.update!(status: :approved, approved_at: Time.current)
    Orders::DeliverableMaterializer.new(order:).call.sole
  end
  let!(:group) { organization.user_groups.create!(name: "Editors") }
  let!(:workflow) do
    board.board_workflows.create!(organization:, name: "Complete action workflow", trigger_key: "order_approved",
                                  enabled: false, created_by: manager)
  end
  let!(:run) do
    workflow.runs.create!(organization:, order:, idempotency_key: "action-matrix-#{SecureRandom.uuid}",
                          triggered_at: Time.current)
  end

  it "executes the complete action pipeline and keeps one canonical deliverable link" do
    workflow.actions.create!(action_type: "create_parent_task", configuration: { "title" => "Production" }, position: 0)
    workflow.actions.create!(action_type: "create_or_group_child_task", configuration: { "customer_visible" => true },
                             position: 1)
    workflow.actions.create!(action_type: "place_on_board",
                             configuration: { "board_id" => secondary_board.id, "column_key" => "in_progress" },
                             position: 2)
    workflow.actions.create!(action_type: "link_deliverable", configuration: {}, position: 3)
    workflow.actions.create!(action_type: "assign_to_user", configuration: { "user_id" => manager.id }, position: 4)
    workflow.actions.create!(action_type: "assign_to_group", configuration: { "user_group_id" => group.id }, position: 5)

    expect { described_class.new(run:).call }.to change(WorkflowTask, :count).by(2)

    parent = WorkflowTask.find_by!(workflow_group_key: "workflow:#{run.id}:parent")
    child = WorkflowTask.find_by!(workflow_group_key: "deliverable:#{deliverable.materialization_key}")

    expect(run.reload).to be_succeeded
    expect(run.steps.order(:position).pluck(:status)).to all(eq("succeeded"))
    expect(parent.child_tasks).to contain_exactly(child)
    expect(child).to have_attributes(assignee: manager, customer_visible: true)
    expect(child.metadata).to include("assigned_group_id" => group.id)
    expect(child.workflow_task_placements.find_by!(board: secondary_board)).to have_attributes(
      workflow_column: secondary_board.workflow_columns.find_by!(key: "in_progress"), is_home: false
    )
    expect(child.workflow_task_deliverables.where(order_deliverable: deliverable).count).to eq(1)
  end
end
