require "rails_helper"

RSpec.describe "Board workflow condition API scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Condition API agency", slug: "condition-api-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Condition API manager", email: "condition-api-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Condition API client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "40 Condition Street") }
  let!(:photography) do
    organization.products.create!(slug: "condition-api-photography", title: "Standard Property Photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:video) do
    organization.products.create!(slug: "condition-api-video", title: "Standard Property Video", kind: :service,
                                  deliverable_type: "video", sla_days: 3)
  end
  let!(:package) do
    organization.products.create!(slug: "condition-api-package", title: "Photo and video package", kind: :package).tap do |product|
      product.product_variants.create!(title: "Standard", price_cents: 60_000, sqft_min: 0, sqft_max: 1_000)
      product.package_components.create!(organization:, service_product: photography, position: 0)
      product.package_components.create!(organization:, service_product: video, position: 1)
    end
  end
  let!(:board) { organization.default_board }

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.where(is_default: true).update_all(enabled: false)
    sign_in manager
  end

  def workflow_params(name:, conditions:, actions: [])
    {
      board_workflow: {
        name:, trigger_key: "order_approved", enabled: true,
        conditions_attributes: conditions,
        actions_attributes: actions,
        status_mappings_attributes: BoardWorkflow.default_status_mapping_attributes(board)
      }
    }
  end

  it "round-trips a scalar condition through the public API" do
    post "/api/v1/boards/#{board.id}/workflows", params: workflow_params(
      name: "Photography only",
      conditions: [ { field: "deliverable_type", operator: "equals", value: "photography", position: 0 } ]
    )

    expect(response).to have_http_status(:created)
    workflow = BoardWorkflow.find(response.parsed_body.dig("board_workflow", "id"))
    condition = workflow.conditions.sole

    expect(condition.value).to eq("photography")
    expect(response.parsed_body.dig("board_workflow", "conditions").sole.fetch("value")).to eq("photography")
  end

  it "accepts an in-list condition and uses it to filter package deliverables during approval" do
    post "/api/v1/boards/#{board.id}/workflows", params: workflow_params(
      name: "Selected services",
      conditions: [ { field: "deliverable_type", operator: "in", value: %w[photography], position: 0 } ],
      actions: [ { action_type: "create_or_group_child_task", configuration: { customer_visible: true }, position: 0 } ]
    )
    expect(response).to have_http_status(:created)

    post "/api/v1/orders", params: {
      order: {
        client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
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
    expect(order.order_deliverables.pluck(:deliverable_type)).to contain_exactly("photography", "video")
    expect(WorkflowTask.where(organization:, task_kind: "deliverable").joins(:order_deliverables)
      .where(order_deliverables: { order_id: order.id }).count).to eq(1)
    expect(WorkflowTask.where(organization:, task_kind: "deliverable").joins(:order_deliverables)
      .where(order_deliverables: { order_id: order.id }).first.order_deliverables.sole.deliverable_type).to eq("photography")
  end

  it "increments the workflow version when a condition is changed through the API" do
    post "/api/v1/boards/#{board.id}/workflows", params: workflow_params(
      name: "Versioned condition",
      conditions: [ { field: "deliverable_type", operator: "equals", value: "photography", position: 0 } ]
    )
    workflow = BoardWorkflow.find(response.parsed_body.dig("board_workflow", "id"))
    old_version = workflow.workflow_version
    condition = workflow.conditions.sole

    patch "/api/v1/boards/#{board.id}/workflows/#{workflow.id}", params: {
      board_workflow: {
        conditions_attributes: [ { id: condition.id, field: "deliverable_type", operator: "equals", value: "video", position: 0 } ]
      }
    }

    expect(response).to have_http_status(:ok)
    expect(workflow.reload).to have_attributes(workflow_version: old_version + 1)
    expect(condition.reload.value).to eq("video")
  end
end
