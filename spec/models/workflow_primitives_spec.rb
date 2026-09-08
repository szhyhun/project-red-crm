require "rails_helper"

RSpec.describe "workflow primitive models" do
  let!(:organization) { Organization.create!(name: "Workflow Primitive Agency", slug: "workflow-primitive-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Workflow Primitive", slug: "other-workflow-primitive") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Workflow client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "9 Workflow Street") }
  let!(:service) do
    organization.products.create!(slug: "primitive-photo", title: "Primitive photography", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:package) do
    organization.products.create!(slug: "primitive-package", title: "Primitive package", kind: :package).tap do |product|
      product.package_components.create!(organization:, service_product: service, position: 0)
    end
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 10_000) }
  let!(:package_variant) { package.product_variants.create!(title: "Standard", price_cents: 18_000) }
  let!(:order) { Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later) }
  let!(:order_item) do
    order.order_items.create!(product: package, product_variant: package_variant, title: "Primitive package", quantity: 1,
                              unit_price_cents: 18_000, total_cents: 18_000)
  end
  let!(:deliverable) do
    order.order_deliverables.create!(organization:, listing:, order_item:, service_product: service,
                                     title: service.title, deliverable_type: "photography", sla_days: 0,
                                     product_component: package.package_components.first,
                                     materialization_key: "primitive-deliverable-#{SecureRandom.uuid}")
  end

  it "matches equals, not-equals, and in conditions against a deliverable" do
    equals = BoardWorkflowCondition.new(field: "deliverable_type", operator: "equals", value: { "value" => "photography" })
    not_equals = BoardWorkflowCondition.new(field: "deliverable_type", operator: "not_equals", value: "video")
    included = BoardWorkflowCondition.new(field: "service_product_id", operator: "in", value: [ service.id.to_s, "999" ])

    expect(equals.matches?(deliverable)).to be(true)
    expect(not_equals.matches?(deliverable)).to be(true)
    expect(included.matches?(deliverable)).to be(true)
  end

  it "matches a package condition through the included component" do
    condition = BoardWorkflowCondition.new(field: "package_product_id", operator: "equals", value: package.id.to_s)

    expect(condition.matches?(deliverable)).to be(true)
  end

  it "does not match a condition with an unsupported operator or field" do
    invalid_operator = BoardWorkflowCondition.new(field: "deliverable_type", operator: "contains", value: "photo")
    invalid_field = BoardWorkflowCondition.new(field: "unknown", operator: "equals", value: "photo")

    expect(invalid_operator).not_to be_valid
    expect(invalid_field).not_to be_valid
    expect(invalid_operator.matches?(deliverable)).to be(false)
    expect(invalid_field.matches?(deliverable)).to be(false)
  end

  it "maps board columns to customer delivery states" do
    board = organization.default_board

    expect(board.workflow_columns.find_by!(key: "todo").canonical_status).to eq("not_started")
    expect(board.workflow_columns.find_by!(key: "in_progress").canonical_status).to eq("in_progress")
    expect(board.workflow_columns.find_by!(key: "blocked").canonical_status).to eq("in_progress")
    expect(board.workflow_columns.find_by!(key: "done").canonical_status).to eq("delivered")
  end

  it "rejects a workflow attached to another organization's board" do
    foreign_board = other_organization.default_board
    workflow = organization.board_workflows.build(board: foreign_board, name: "Foreign board workflow",
                                                   trigger_key: "order_approved")

    expect(workflow).not_to be_valid
    expect(workflow.errors.full_messages).to include("Board must belong to the same organization")
  end

  it "rejects a placement whose column belongs to a different board" do
    first_board = organization.default_board
    second_board = organization.boards.create!(name: "Second primitive board", kind: :internal, visibility: :organization,
                                               requires_listing: false, client_visible: false, position: 1)
    WorkflowColumn::DEFAULTS.each { |attributes| second_board.workflow_columns.create!(attributes.merge(organization:)) }
    task = second_board.workflow_tasks.create!(organization:, title: "Primitive task", status: "todo")
    placement = task.workflow_task_placements.build(board: second_board,
                                                    workflow_column: first_board.workflow_columns.find_by!(key: "todo"),
                                                    position: 0)

    expect(placement).not_to be_valid
    expect(placement.errors.full_messages).to include("Workflow column must belong to the selected board")
  end

  it "rejects a task-deliverable link across organizations" do
    board = organization.default_board
    task = board.workflow_tasks.create!(organization:, listing:, title: "Primitive task", status: "todo")
    foreign_client = ClientAccount.create!(organization: other_organization, name: "Foreign workflow client", kind: :agent)
    foreign_order = Order.create!(organization: other_organization, client_account: foreign_client)
    foreign_service = other_organization.products.create!(slug: "foreign-primitive-service", title: "Foreign service",
                                                           kind: :service, deliverable_type: "video")
    foreign_item = foreign_order.order_items.create!(product: foreign_service, title: "Foreign service", quantity: 1,
                                                     unit_price_cents: 1, total_cents: 1)
    foreign_deliverable = foreign_order.order_deliverables.build(
      organization: other_organization, order_item: foreign_item, service_product: foreign_service,
      title: "Foreign service", deliverable_type: "video", sla_days: 0,
      materialization_key: "foreign-primitive-deliverable-#{SecureRandom.uuid}"
    )
    link = task.workflow_task_deliverables.build(order_deliverable: foreign_deliverable, position: 0)

    expect(link).not_to be_valid
    expect(link.errors.full_messages).to include("task and deliverable must belong to the same organization")
  end
end
