require "rails_helper"

RSpec.describe Workflows::Runner do
  let!(:organization) { Organization.create!(name: "Condition runner agency", slug: "condition-runner-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Condition runner client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "60 Condition Runner Street") }
  let!(:photography) do
    organization.products.create!(slug: "condition-runner-photography", title: "Property photography",
                                  kind: :service, deliverable_type: "photography")
  end
  let!(:video) do
    organization.products.create!(slug: "condition-runner-video", title: "Property video", kind: :service,
                                  deliverable_type: "video")
  end
  let!(:package) do
    organization.products.create!(slug: "condition-runner-package", title: "Media package", kind: :package,
                                  deliverable_type: "other").tap do |product|
      product.product_variants.create!(title: "Standard", price_cents: 50_000)
      product.package_components.create!(organization:, service_product: photography, position: 0)
      product.package_components.create!(organization:, service_product: video, position: 1)
    end
  end
  let!(:photo_variant) { photography.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:package_variant) { package.product_variants.sole }
  let!(:board) { organization.default_board }
  let!(:workflow) do
    board.board_workflows.create!(organization:, name: "Condition runner workflow", trigger_key: "order_approved",
                                  enabled: false)
  end

  def order_with_package_and_standalone
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                  status: :approved, approved_at: Time.current).tap do |order|
      package_item = order.order_items.create!(product: package, product_variant: package_variant,
                                                title: package.title, quantity: 1, unit_price_cents: 50_000,
                                                total_cents: 50_000, snapshot: OrderItem.catalog_snapshot(package_variant))
      standalone_item = order.order_items.create!(product: photography, product_variant: photo_variant,
                                                   title: photography.title, quantity: 1, unit_price_cents: 20_000,
                                                   total_cents: 20_000, snapshot: OrderItem.catalog_snapshot(photo_variant))
      package_item
      standalone_item
    end
  end

  def run_for(order)
    Orders::DeliverableMaterializer.new(order:).call
    workflow.runs.create!(organization:, order:, idempotency_key: "condition-runner-#{SecureRandom.uuid}",
                          triggered_at: Time.current)
  end

  it "uses package identity to exclude a standalone purchase of the same service" do
    order = order_with_package_and_standalone
    run = run_for(order)
    workflow.conditions.create!(field: "package_product_id", operator: "equals", value: package.id, position: 0)
    workflow.actions.create!(action_type: "create_or_group_child_task", configuration: {}, position: 0)

    described_class.new(run:).call

    tasks = WorkflowTask.where(organization:, task_kind: "deliverable").joins(:order_deliverables)
    expect(tasks.count).to eq(2)
    expect(tasks.map(&:order_deliverables).flatten).to all(satisfy { |deliverable| deliverable.product_component.present? })
    expect(tasks.map(&:order_deliverables).flatten.map(&:service_product_id)).to contain_exactly(photography.id, video.id)
  end

  it "uses service identity to select one included service from a package" do
    order = order_with_package_and_standalone
    run = run_for(order)
    workflow.conditions.create!(field: "service_product_id", operator: "equals", value: video.id, position: 0)
    workflow.actions.create!(action_type: "create_or_group_child_task", configuration: {}, position: 0)

    described_class.new(run:).call

    task = WorkflowTask.where(organization:, task_kind: "deliverable").sole
    expect(task.order_deliverables.sole).to have_attributes(service_product: video, product_component: be_present)
  end

  it "requires every condition before creating a child task" do
    order = order_with_package_and_standalone
    run = run_for(order)
    workflow.conditions.create!(field: "deliverable_type", operator: "equals", value: "video", position: 0)
    workflow.conditions.create!(field: "service_product_id", operator: "equals", value: photography.id, position: 1)
    workflow.actions.create!(action_type: "create_or_group_child_task", configuration: {}, position: 0)

    described_class.new(run:).call

    expect(run.reload).to be_succeeded
    expect(WorkflowTask.where(organization:, task_kind: "deliverable")).to be_empty
    expect(run.steps.sole.output).to include("task_ids" => [], "deliverable_ids" => [])
  end
end
