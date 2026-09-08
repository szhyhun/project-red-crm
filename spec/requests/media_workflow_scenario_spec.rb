require "rails_helper"

RSpec.describe "Media workflow acceptance scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Scenario Agency", slug: "scenario-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Scenario Manager", email: "scenario-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Scenario client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Scenario client user", email: "scenario-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "16 Scenario Street") }
  let!(:photography) do
    organization.products.create!(slug: "scenario-photography", title: "Standard property photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:video) do
    organization.products.create!(slug: "scenario-video", title: "Standard property video", kind: :service,
                                  deliverable_type: "video", sla_days: 3)
  end
  let!(:package) do
    organization.products.create!(slug: "scenario-package", title: "Photo and video package", kind: :package).tap do |product|
      product.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 60_000, sqft_min: 0, sqft_max: 1_000)
      product.package_components.create!(organization:, service_product: photography, position: 0)
      product.package_components.create!(organization:, service_product: video, position: 1)
    end
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    sign_in manager
  end

  it "materializes a package, runs the board workflow, and exposes a safe customer change request" do
    post "/api/v1/orders", params: {
      order: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: package.product_variants.sole.id, quantity: 1 } ]
      }
    }
    expect(response).to have_http_status(:created)
    order_id = response.parsed_body.dig("order", "id")

    perform_enqueued_jobs(only: BoardWorkflowJob) do
      post "/api/v1/orders/#{order_id}/approve"
    end

    expect(response).to have_http_status(:ok)
    order = Order.find(order_id)
    expect(order).to be_approved
    expect(order.order_items.count).to eq(1)
    expect(order.order_deliverables.pluck(:deliverable_type)).to eq(%w[photography video])
    expect(order.order_deliverables.pluck(:scope_label)).to eq([ "0–1,000 sqft", "0–1,000 sqft" ])
    expect(BoardWorkflowRun.where(order:).sole).to be_succeeded
    workflow_tasks = WorkflowTask.where(organization:, listing:)
    expect(workflow_tasks.where(task_kind: "parent").count).to eq(1)
    expect(workflow_tasks.where(task_kind: "deliverable").count).to eq(2)
    expect(workflow_tasks.joins(:order_deliverables).count).to eq(2)

    photography_deliverable = order.order_deliverables.find_by!(service_product: photography)
    photography_task = workflow_tasks.joins(:order_deliverables).find_by!(order_deliverables: { id: photography_deliverable.id })
    patch "/api/v1/workflow_tasks/#{photography_task.id}", params: {
      workflow_task: { status: "done", position: 0 }
    }

    expect(response).to have_http_status(:ok)
    expect(photography_task.reload).to have_attributes(status: "done", completed_at: be_present)
    expect(photography_deliverable.reload).to have_attributes(status: "delivered", delivered_at: be_present)
    expect(photography_task.workflow_task_placements.where(is_home: true).sole.workflow_column.key).to eq("done")

    asset = photography_deliverable.media_assets.create!(organization:, listing:, order:,
                                                          order_item: order.order_items.sole, kind: :final,
                                                          status: :ready,
                                                          source_url: "https://cdn.example.test/scenario-front.jpg",
                                                          filename: "scenario-front.jpg", content_type: "image/jpeg",
                                                          customer_visible: true)
    photography_deliverable.update!(status: :delivered, delivered_at: Time.current)

    sign_out manager
    sign_in client_user
    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    portal_deliverable = response.parsed_body.fetch("deliverables").find { |entry| entry["id"] == photography_deliverable.id }
    expect(portal_deliverable).to include("status" => "delivered", "can_request_changes" => true, "asset_count" => 1)
    expect(portal_deliverable.dig("assets", 0)).to include(
      "id" => asset.id,
      "preview_path" => "/api/v1/media_assets/#{asset.id}/preview",
      "download_path" => "/api/v1/media_assets/#{asset.id}/download"
    )

    post "/api/v1/portal/listings/#{listing.id}/deliverables/#{photography_deliverable.id}/change_requests", params: {
      change_request: { body_html: "<p>Please replace the exterior photo.</p>", media_asset_ids: [ asset.id ] }
    }

    expect(response).to have_http_status(:created)
    expect(photography_deliverable.reload).to be_in_progress
    message = Message.find(response.parsed_body.dig("change_request", "message_id"))
    expect(message).to have_attributes(message_kind: "change_request", listing_id: listing.id,
                                       order_deliverable_id: photography_deliverable.id)
    expect(message.referenced_media_assets).to contain_exactly(asset)
  end
end
