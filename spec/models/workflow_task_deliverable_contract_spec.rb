require "rails_helper"

RSpec.describe WorkflowTaskDeliverable, type: :model do
  let!(:organization) { Organization.create!(name: "Task link agency", slug: "task-link-agency") }
  let!(:other_organization) { Organization.create!(name: "Other task link agency", slug: "other-task-link-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Task link client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "12 Task Link Street") }
  let!(:service) do
    organization.products.create!(slug: "task-link-service", title: "Task link photography", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:order) { Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later) }
  let!(:order_item) do
    order.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                              unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
  end
  let!(:deliverable) do
    order.order_deliverables.create!(organization:, listing:, order_item:, service_product: service,
                                     title: service.title, deliverable_type: service.deliverable_type,
                                     materialization_key: "task-link-#{SecureRandom.uuid}")
  end
  let!(:task) do
    organization.default_board.workflow_tasks.create!(organization:, listing:, title: "Produce the photos", status: "todo")
  end

  it "links one production task to one deliverable with an explicit order" do
    link = task.workflow_task_deliverables.create!(order_deliverable: deliverable, position: 2)

    expect(link).to have_attributes(workflow_task: task, order_deliverable: deliverable, position: 2)
    expect(task.reload.order_deliverables).to contain_exactly(deliverable)
  end

  it "rejects a second link for the same task and deliverable" do
    task.workflow_task_deliverables.create!(order_deliverable: deliverable, position: 0)
    duplicate = task.workflow_task_deliverables.build(order_deliverable: deliverable, position: 1)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors.full_messages).to include("Order deliverable has already been taken")
    expect {
      duplicate.save!(validate: false)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "rejects a link that crosses organization boundaries" do
    foreign_client = ClientAccount.create!(organization: other_organization, name: "Foreign task link client", kind: :agent)
    foreign_order = Order.create!(organization: other_organization, client_account: foreign_client, payment_mode: :pay_later)
    foreign_service = other_organization.products.create!(slug: "foreign-task-link-service", title: "Foreign service",
                                                           kind: :service, deliverable_type: "video")
    foreign_item = foreign_order.order_items.create!(product: foreign_service, title: foreign_service.title, quantity: 1,
                                                     unit_price_cents: 1_000, total_cents: 1_000)
    foreign_deliverable = foreign_order.order_deliverables.build(
      organization: other_organization, order_item: foreign_item, service_product: foreign_service,
      title: foreign_service.title, deliverable_type: "video", materialization_key: "foreign-task-link-#{SecureRandom.uuid}"
    )
    foreign_deliverable.save!(validate: false)
    link = task.workflow_task_deliverables.build(order_deliverable: foreign_deliverable, position: 0)

    expect(link).not_to be_valid
    expect(link.errors.full_messages).to include("task and deliverable must belong to the same organization")
  end

  it "requires non-negative positions" do
    link = task.workflow_task_deliverables.build(order_deliverable: deliverable, position: -1)

    expect(link).not_to be_valid
    expect(link.errors[:position]).to include("must be greater than or equal to 0")
  end
end
