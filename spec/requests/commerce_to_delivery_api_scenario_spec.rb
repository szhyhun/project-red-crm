require "rails_helper"

RSpec.describe "Commerce to delivery API scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Commerce delivery agency", slug: "commerce-delivery-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Commerce manager", email: "commerce-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Commerce client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "91 Commerce Street") }
  let!(:board) { organization.default_board }

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.update_all(enabled: false)
    sign_in manager
  end

  it "runs a package and an add-on through approval without double billing" do
    photography = create_product(
      slug: "commerce-photography",
      title: "Standard property photography",
      kind: "service",
      deliverable_type: "photography",
      sla_days: 2,
      product_variants_attributes: [
        { title: "Up to 1,000 sqft", price_cents: 30_000, sqft_min: 0, sqft_max: 1_000 }
      ]
    )
    video = create_product(
      slug: "commerce-video",
      title: "Standard property video",
      kind: "service",
      deliverable_type: "video",
      sla_days: 3,
      product_variants_attributes: [ { title: "Flat rate", price_cents: 24_000 } ]
    )
    add_on = create_product(
      slug: "commerce-drone-addon",
      title: "Drone stills add-on",
      kind: "addon",
      deliverable_type: "drone",
      sla_days: 1,
      product_variants_attributes: [ { title: "Standard", price_cents: 8_000 } ]
    )
    package = create_product(
      slug: "commerce-media-package",
      title: "Complete media package",
      kind: "package",
      deliverable_type: "other",
      product_variants_attributes: [
        { title: "Up to 1,000 sqft", price_cents: 49_000, sqft_min: 0, sqft_max: 1_000 }
      ]
    )

    [ photography, video ].each_with_index do |service, position|
      post "/api/v1/products/#{package.fetch("id")}/components", params: {
        product_component: { service_product_id: service.fetch("id"), quantity: 1, position: }
      }
      expect(response).to have_http_status(:created)
    end

    post "/api/v1/boards/#{board.id}/workflows", params: {
      board_workflow: {
        name: "Commerce delivery workflow",
        trigger_key: "order_approved",
        enabled: true,
        status_mappings_attributes: BoardWorkflow.default_status_mapping_attributes(board),
        actions_attributes: [
          { action_type: "create_parent_task", configuration: { title: "Production" }, position: 0 },
          { action_type: "create_or_group_child_task", configuration: { customer_visible: true }, position: 1 }
        ]
      }
    }
    expect(response).to have_http_status(:created)

    post "/api/v1/orders", params: {
      order: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [
          { product_variant_id: package.fetch("variants").sole.fetch("id"), quantity: 1 },
          { product_variant_id: add_on.fetch("variants").sole.fetch("id"), quantity: 1 }
        ]
      }
    }
    expect(response).to have_http_status(:created)
    order_id = response.parsed_body.dig("order", "id")

    perform_enqueued_jobs(only: BoardWorkflowJob) do
      post "/api/v1/orders/#{order_id}/approve"
    end

    expect(response).to have_http_status(:ok)
    order = Order.find(order_id)
    deliverables = order.order_deliverables.ordered

    expect(order.order_items.count).to eq(2)
    expect(order.reload).to have_attributes(status: "approved", subtotal_cents: 57_000, total_cents: 57_000)
    expect(deliverables.map(&:service_product_id)).to eq([ photography.fetch("id"), video.fetch("id"), add_on.fetch("id") ])
    expect(deliverables.first(2).map(&:product_component_id)).to all(be_present)
    expect(deliverables.last.product_component_id).to be_nil
    expect(deliverables.first.scope_label).to eq("0–1,000 sqft")
    expect(deliverables.map(&:status)).to all(eq("not_started"))

    expect(WorkflowTask.where(organization:, task_kind: "parent").count).to eq(1)
    expect(WorkflowTask.where(organization:, task_kind: "deliverable").count).to eq(3)
    expect(WorkflowTaskDeliverable.where(order_deliverable_id: deliverables.ids).count).to eq(3)
    expect(WorkflowTaskPlacement.where(workflow_task: WorkflowTask.where(organization:)).count).to eq(4)

    invoice = Invoices::Creator.new(organization:, order:).create!
    expect(invoice).to have_attributes(subtotal_cents: 57_000, total_cents: 57_000, balance_due_cents: 57_000)
    expect(order.reload).to be_invoiced

    get "/api/v1/orders/#{order.id}/deliverables"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("order_deliverables").map { |item| item.fetch("title") }).to eq(
      [ "Standard property photography", "Standard property video", "Drone stills add-on" ]
    )
  end

  it "does not let an order select a variant from another organization" do
    other_organization = Organization.create!(name: "Other commerce agency", slug: "other-commerce-agency")
    other_product = other_organization.products.create!(slug: "foreign-service", title: "Foreign service", kind: :service)
    foreign_variant = other_product.product_variants.create!(title: "Standard", price_cents: 10_000)

    expect {
      post "/api/v1/orders", params: {
        order: {
          client_account_id: client_account.id,
          listing_id: listing.id,
          payment_mode: "pay_later",
          items: [ { product_variant_id: foreign_variant.id, quantity: 1 } ]
        }
      }
    }.not_to change(Order, :count)

    expect(response).to have_http_status(:not_found)
  end

  private

  def create_product(attributes)
    post "/api/v1/products", params: { product: attributes }
    expect(response).to have_http_status(:created)

    response.parsed_body.fetch("product")
  end
end
