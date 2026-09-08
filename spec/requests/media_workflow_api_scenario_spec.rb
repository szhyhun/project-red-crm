require "rails_helper"

RSpec.describe "Media workflow API lifecycle", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Lifecycle Agency", slug: "lifecycle-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Lifecycle Manager", email: "lifecycle-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Lifecycle Client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Lifecycle Client User", email: "lifecycle-client@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "20 Lifecycle Street") }
  let!(:service) do
    organization.products.create!(slug: "lifecycle-photography", title: "Property photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) do
    service.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 30_000, sqft_min: 0, sqft_max: 1_000)
  end
  let!(:board) { organization.default_board }

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.where(is_default: true).update_all(enabled: false)
    sign_in manager
  end

  it "runs an API-configured workflow from approval through a customer-visible delivery" do
    post "/api/v1/boards/#{board.id}/workflows", params: {
      board_workflow: {
        name: "Lifecycle production automation",
        trigger_key: "order_approved",
        enabled: true,
        status_mappings_attributes: BoardWorkflow.default_status_mapping_attributes(board),
        actions_attributes: [
          { action_type: "create_parent_task", configuration: { title: "Production" }, position: 0 },
          { action_type: "create_or_group_child_task", configuration: { customer_visible: true }, position: 1 },
          { action_type: "place_on_board", configuration: { board_id: board.id, column_key: "todo" }, position: 2 }
        ]
      }
    }

    expect(response).to have_http_status(:created)
    workflow_id = response.parsed_body.dig("board_workflow", "id")

    post "/api/v1/orders", params: {
      order: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: variant.id, quantity: 1 } ]
      }
    }

    expect(response).to have_http_status(:created)
    order_id = response.parsed_body.dig("order", "id")

    perform_enqueued_jobs(only: BoardWorkflowJob) do
      post "/api/v1/orders/#{order_id}/approve"
    end

    expect(response).to have_http_status(:ok)
    order = Order.find(order_id)
    deliverable = order.order_deliverables.sole
    workflow = BoardWorkflow.find(workflow_id)
    run = workflow.runs.find_by!(order: order)
    task = WorkflowTask.joins(:order_deliverables).find_by!(order_deliverables: { id: deliverable.id })

    expect(run).to be_succeeded
    expect(task).to have_attributes(task_kind: "deliverable", customer_visible: true, status: "todo")
    expect(task.home_placement).to have_attributes(board_id: board.id,
                                                   workflow_column: board.workflow_columns.find_by!(key: "todo"))

    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { status: "done", position: 0 }
    }

    expect(response).to have_http_status(:ok)
    expect(deliverable.reload).to have_attributes(status: "delivered", delivered_at: be_present)

    visible_asset = deliverable.media_assets.create!(
      organization:, listing:, order:, order_item: order.order_items.sole,
      kind: :final, status: :ready, storage_key: "organizations/#{organization.id}/deliverables/#{deliverable.id}/front.jpg",
      filename: "front.jpg", content_type: "image/jpeg", customer_visible: true
    )

    sign_out manager
    sign_in client_user
    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("deliverables", 0)).to include(
      "id" => deliverable.id,
      "status" => "delivered",
      "can_request_changes" => true
    )
    expect(response.parsed_body.dig("deliverables", 0, "assets")).to include(
      hash_including(
        "id" => visible_asset.id,
        "preview_path" => "/api/v1/media_assets/#{visible_asset.id}/preview",
        "download_path" => "/api/v1/media_assets/#{visible_asset.id}/download"
      )
    )
  end

  it "rejects an API workflow that is enabled without complete status mappings" do
    post "/api/v1/boards/#{board.id}/workflows", params: {
      board_workflow: { name: "Unsafe automation", trigger_key: "order_approved", enabled: true }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "status_mappings").join).to include("delivered")
    expect(board.board_workflows.find_by(name: "Unsafe automation")).to be_nil
  end
end
