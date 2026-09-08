require "rails_helper"

RSpec.describe "Package workflow API scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Package workflow agency", slug: "package-workflow-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Package workflow manager", email: "package-workflow-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Package workflow client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Package workflow customer", email: "package-workflow-client@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "80 Package Workflow Street") }
  let!(:board) { organization.default_board }

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.update_all(enabled: false)
    sign_in manager
  end

  it "creates one billed package, separate service deliverables, and linked production tasks" do
    post "/api/v1/products", params: {
      product: {
        slug: "package-workflow-photography", title: "Standard property photography", kind: "service",
        deliverable_type: "photography", sla_days: 2,
        product_variants_attributes: [ { title: "Up to 1,000 sqft", price_cents: 30_000,
                                         sqft_min: 0, sqft_max: 1_000 } ]
      }
    }
    expect(response).to have_http_status(:created)
    photography = Product.find(response.parsed_body.dig("product", "id"))
    photography_variant_id = response.parsed_body.dig("product", "variants", 0, "id")

    post "/api/v1/products", params: {
      product: {
        slug: "package-workflow-video", title: "Standard property video", kind: "service",
        deliverable_type: "video", sla_days: 3,
        product_variants_attributes: [ { title: "Up to 1,000 sqft", price_cents: 24_000,
                                         sqft_min: 0, sqft_max: 1_000 } ]
      }
    }
    expect(response).to have_http_status(:created)
    video = Product.find(response.parsed_body.dig("product", "id"))
    video_variant_id = response.parsed_body.dig("product", "variants", 0, "id")

    post "/api/v1/products", params: {
      product: {
        slug: "package-workflow-package", title: "Complete media package", kind: "package",
        deliverable_type: "other",
        product_variants_attributes: [ { title: "Up to 1,000 sqft", price_cents: 49_000,
                                         sqft_min: 0, sqft_max: 1_000 } ]
      }
    }
    expect(response).to have_http_status(:created)
    package = Product.find(response.parsed_body.dig("product", "id"))
    package_variant_id = response.parsed_body.dig("product", "variants", 0, "id")

    [ photography, video ].each_with_index do |service, position|
      post "/api/v1/products/#{package.id}/components", params: {
        product_component: { service_product_id: service.id, quantity: 1, position: }
      }
      expect(response).to have_http_status(:created)
    end

    post "/api/v1/boards/#{board.id}/workflows", params: {
      board_workflow: {
        name: "Package production workflow", trigger_key: "order_approved", enabled: true,
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
        client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
        items: [ { product_variant_id: package_variant_id, quantity: 1 } ]
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
    expect(order.order_items).to contain_exactly(have_attributes(product_id: package.id, total_cents: 49_000))
    expect(order.reload).to have_attributes(subtotal_cents: 49_000, total_cents: 49_000, status: "approved")
    expect(deliverables.map(&:service_product_id)).to eq([ photography.id, video.id ])
    expect(deliverables.map(&:scope_label)).to eq([ "0–1,000 sqft", "0–1,000 sqft" ])
    expect(deliverables.map(&:product_component_id)).to eq(package.package_components.ordered.ids)
    expect(WorkflowTask.where(organization:, task_kind: "parent").count).to eq(1)
    expect(WorkflowTask.where(organization:, task_kind: "deliverable").count).to eq(2)
    expect(WorkflowTaskDeliverable.where(order_deliverable_id: deliverables.ids).count).to eq(2)
    expect(WorkflowTaskPlacement.where(workflow_task: WorkflowTask.where(organization:)).count).to eq(3)

    invoice = Invoices::Creator.new(organization:, order:).create!
    expect(invoice).to have_attributes(subtotal_cents: 49_000, total_cents: 49_000, balance_due_cents: 49_000)
    expect(order.reload).to be_invoiced

    sign_out manager
    sign_in client_user
    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("summary")).to include("deliverable_count" => 2, "delivered_count" => 0)
    expect(response.parsed_body.fetch("deliverables").pluck("title")).to contain_exactly(
      "Standard property photography", "Standard property video"
    )
  end
end
