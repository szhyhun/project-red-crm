require "rails_helper"

RSpec.describe "Catalog to customer portal API scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "API scenario agency", slug: "api-scenario-agency") }
  let!(:manager) do
    User.create!(organization:, name: "API scenario manager", email: "api-scenario-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "API scenario client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "API scenario client user", email: "api-scenario-client@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "99 API Scenario Street") }

  before do
    ActiveJob::Base.queue_adapter = :test
    sign_in manager
  end

  it "runs a package from catalog APIs through approval, workflow, task movement, and portal status" do
    post "/api/v1/products", params: {
      product: {
        slug: "api-scenario-photography",
        title: "Standard Property Photography",
        description: "Interior and exterior property photos.",
        kind: "service",
        deliverable_type: "photography",
        sla_days: 2,
        product_variants_attributes: [
          { title: "0–1,000 sqft", price_cents: 29_900, sqft_min: 0, sqft_max: 1_000 }
        ]
      }
    }
    expect(response).to have_http_status(:created)
    service_payload = response.parsed_body.fetch("product")
    service_id = service_payload.fetch("id")
    service_variant_id = service_payload.fetch("variants").sole.fetch("id")

    post "/api/v1/products", params: {
      product: {
        slug: "api-scenario-package",
        title: "Photo and video package",
        description: "A single package with two production services.",
        kind: "package",
        deliverable_type: "other",
        product_variants_attributes: [
          { title: "0–1,000 sqft", price_cents: 59_900, sqft_min: 0, sqft_max: 1_000 }
        ]
      }
    }
    expect(response).to have_http_status(:created)
    package_payload = response.parsed_body.fetch("product")
    package_id = package_payload.fetch("id")
    package_variant_id = package_payload.fetch("variants").sole.fetch("id")

    post "/api/v1/products/#{package_id}/components", params: {
      product_component: { service_product_id: service_id, quantity: 1, position: 0 }
    }
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig("component", "service_product", "id")).to eq(service_id)

    get "/api/v1/products/#{package_id}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("product", "components").sole).to include(
      "service_product" => hash_including("id" => service_id, "title" => "Standard Property Photography")
    )

    post "/api/v1/orders", params: {
      order: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: package_variant_id, quantity: 1 } ]
      }
    }
    expect(response).to have_http_status(:created)
    order_id = response.parsed_body.dig("order", "id")

    perform_enqueued_jobs(only: BoardWorkflowJob) do
      post "/api/v1/orders/#{order_id}/approve"
    end

    expect(response).to have_http_status(:ok)
    order_payload = response.parsed_body.fetch("order")
    order = Order.find(order_id)
    deliverables = order.order_deliverables.ordered
    expect(order_payload).to include("status" => "approved", "approved_at" => be_present)
    expect(order.order_items.count).to eq(1)
    expect(deliverables.map(&:service_product_id)).to eq([ service_id ])
    expect(deliverables.sole).to have_attributes(scope_sqft_min: 0, scope_sqft_max: 1_000, scope_label: "0–1,000 sqft")
    expect(order_payload.fetch("deliverables").sole.fetch("task_ids")).to be_present
    expect(WorkflowTask.where(listing:).pluck(:task_kind)).to contain_exactly("parent", "deliverable")

    photography_task_id = order_payload.fetch("deliverables").sole.fetch("task_ids").sole
    patch "/api/v1/workflow_tasks/#{photography_task_id}", params: {
      workflow_task: { status: "done", position: 0 }
    }
    expect(response).to have_http_status(:ok)
    expect(OrderDeliverable.find(deliverables.sole.id)).to be_delivered

    sign_out manager
    sign_in client_user
    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    portal_payload = response.parsed_body
    portal_deliverable = portal_payload.fetch("deliverables").sole
    expect(portal_payload.fetch("summary")).to include("deliverable_count" => 1, "delivered_count" => 1)
    expect(portal_deliverable).to include(
      "title" => "Standard Property Photography",
      "status" => "delivered",
      "asset_count" => 0,
      "can_request_changes" => true
    )
  end
end
