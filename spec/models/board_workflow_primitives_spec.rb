require "rails_helper"

RSpec.describe "Board workflow primitives", type: :model do
  let!(:organization) { Organization.create!(name: "Workflow primitive agency", slug: "workflow-primitive-agency") }
  let!(:other_organization) { Organization.create!(name: "Other workflow primitive agency", slug: "other-workflow-primitive-agency") }
  let!(:board) { organization.default_board }
  let!(:other_board) { other_organization.default_board }
  let!(:workflow) do
    board.board_workflows.create!(organization:, name: "Primitive workflow", trigger_key: "order_approved", enabled: false)
  end

  it "accepts every documented action type and orders actions deterministically" do
    BoardWorkflowAction::ACTION_TYPES.each_with_index do |action_type, index|
      workflow.actions.create!(action_type:, position: index)
    end

    expect(workflow.actions.ordered.pluck(:action_type)).to eq(BoardWorkflowAction::ACTION_TYPES)
  end

  it "rejects an unknown action type and a negative position" do
    action = workflow.actions.build(action_type: "send_email", position: -1)

    expect(action).not_to be_valid
    expect(action.errors[:action_type]).to include("is not included in the list")
    expect(action.errors[:position]).to include("must be greater than or equal to 0")
  end

  it "rejects a placement action that targets another organization" do
    action = workflow.actions.build(action_type: "place_on_board",
                                    configuration: { "board_id" => other_board.id, "column_key" => "todo" }, position: 0)

    expect(action).not_to be_valid
    expect(action.errors[:configuration]).to include("target board must belong to the workflow organization")
  end

  it "rejects a placement action that targets a missing board" do
    action = workflow.actions.build(action_type: "place_on_board",
                                    configuration: { "board_id" => 999_999, "column_key" => "todo" }, position: 0)

    expect(action).not_to be_valid
    expect(action.errors[:configuration]).to include("target board must belong to the workflow organization")
  end

  it "rejects assignment actions that target another organization's user or group" do
    foreign_user = User.create!(organization: other_organization, name: "Foreign workflow user",
                                email: "foreign-workflow-user@example.test", password: "long-enough-password",
                                role: :production_staff)
    foreign_group = other_organization.user_groups.create!(name: "Foreign workflow group")

    user_action = workflow.actions.build(action_type: "assign_to_user",
                                         configuration: { "user_id" => foreign_user.id }, position: 0)
    group_action = workflow.actions.build(action_type: "assign_to_group",
                                          configuration: { "user_group_id" => foreign_group.id }, position: 1)

    expect(user_action).not_to be_valid
    expect(user_action.errors[:configuration]).to include("target user must belong to the workflow organization")
    expect(group_action).not_to be_valid
    expect(group_action.errors[:configuration]).to include("target group must belong to the workflow organization")
  end

  it "accepts assignment actions for targets in the workflow organization" do
    user = User.create!(organization:, name: "Local workflow user", email: "local-workflow-user@example.test",
                        password: "long-enough-password", role: :production_staff)
    group = organization.user_groups.create!(name: "Local workflow group")

    expect(workflow.actions.build(action_type: "assign_to_user", configuration: { "user_id" => user.id }, position: 0)).to be_valid
    expect(workflow.actions.build(action_type: "assign_to_group",
                                  configuration: { "user_group_id" => group.id }, position: 1)).to be_valid
  end

  it "accepts a placement action on another board in the same organization" do
    shared_board = organization.boards.create!(name: "Shared primitive board", kind: :internal,
                                               visibility: :organization, requires_listing: false,
                                               client_visible: false, position: 1)
    WorkflowColumn::DEFAULTS.each { |attributes| shared_board.workflow_columns.create!(attributes.merge(organization:)) }
    action = workflow.actions.build(action_type: "place_on_board",
                                    configuration: { "board_id" => shared_board.id, "column_key" => "todo" }, position: 0)

    expect(action).to be_valid
  end

  it "evaluates conditions against relational deliverable data" do
    client_account = ClientAccount.create!(organization:, name: "Primitive client", kind: :agent)
    service = organization.products.create!(slug: "primitive-service", title: "Primitive photography", kind: :service,
                                             deliverable_type: "photography")
    variant = service.product_variants.create!(title: "Standard", price_cents: 10_000)
    order = Order.create!(organization:, client_account:, payment_mode: :pay_later)
    item = order.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                                     unit_price_cents: 10_000, total_cents: 10_000)
    deliverable = order.order_deliverables.create!(organization:, order_item: item, service_product: service,
                                                   title: service.title, deliverable_type: "photography",
                                                   materialization_key: "primitive-deliverable")

    equals = workflow.conditions.create!(field: "deliverable_type", operator: "equals",
                                        value: { "value" => "photography" }, position: 0)
    in_condition = workflow.conditions.build(field: "service_product_id", operator: "in",
                                             value: [ service.id, 999_999 ], position: 1)
    not_equals = workflow.conditions.build(field: "package_product_id", operator: "not_equals",
                                           value: service.id, position: 2)

    expect(equals.matches?(deliverable)).to be(true)
    expect(in_condition.matches?(deliverable)).to be(true)
    expect(not_equals.matches?(deliverable)).to be(true)
  end

  it "rejects unsupported condition fields and operators" do
    condition = workflow.conditions.build(field: "order_total", operator: "contains", position: 0)

    expect(condition).not_to be_valid
    expect(condition.errors[:field]).to include("is not included in the list")
    expect(condition.errors[:operator]).to include("is not included in the list")
  end

  it "requires a status mapping to point at a column on the workflow board" do
    mapping = workflow.status_mappings.build(source_status: "delivered", target_column_key: "missing", position: 0)

    expect(mapping).not_to be_valid
    expect(mapping.errors[:target_column_key]).to include("must match a column on the workflow board")
  end

  it "enforces one mapping per customer-facing source state at the database boundary" do
    workflow.status_mappings.create!(source_status: "delivered", target_column_key: "done", position: 0)

    expect {
      workflow.status_mappings.create!(source_status: "delivered", target_column_key: "todo", position: 1)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
