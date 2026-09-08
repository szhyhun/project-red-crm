require "rails_helper"

RSpec.describe "Workflow multi-board API scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Multi-board agency", slug: "multi-board-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Multi-board manager", email: "multi-board-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Multi-board client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Multi-board customer", email: "multi-board-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "14 Multi-board Street") }
  let!(:home_board) { organization.default_board }
  let!(:review_board) do
    organization.boards.create!(name: "Review board", kind: :internal, visibility: :organization,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:service) do
    organization.products.create!(slug: "multi-board-photography", title: "Multi-board photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.update_all(enabled: false)
    sign_in manager
  end

  it "creates shared placements and synchronizes portal state when the secondary board moves" do
    post "/api/v1/boards/#{home_board.id}/workflows", params: {
      board_workflow: {
        name: "Send work to review",
        trigger_key: "order_approved",
        enabled: true,
        status_mappings_attributes: BoardWorkflow.default_status_mapping_attributes(home_board),
        actions_attributes: [
          { action_type: "create_or_group_child_task", configuration: { customer_visible: true }, position: 0 },
          { action_type: "place_on_board", configuration: { board_id: review_board.id, column_key: "in_progress" }, position: 1 }
        ]
      }
    }
    expect(response).to have_http_status(:created)

    post "/api/v1/orders", params: {
      order: {
        client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
        items: [ { product_variant_id: variant.id, quantity: 1 } ]
      }
    }
    expect(response).to have_http_status(:created)
    order_id = response.parsed_body.dig("order", "id")

    perform_enqueued_jobs(only: BoardWorkflowJob) do
      post "/api/v1/orders/#{order_id}/approve"
    end
    expect(response).to have_http_status(:ok)

    task = WorkflowTask.where(organization:, task_kind: "deliverable").sole
    deliverable = Order.find(order_id).order_deliverables.sole
    expect(task.workflow_task_placements).to contain_exactly(
      have_attributes(board: home_board, is_home: true),
      have_attributes(board: review_board, is_home: false)
    )

    get "/api/v1/boards/#{home_board.id}/workflow_tasks"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("workflow_tasks")).to contain_exactly(
      include("id" => task.id, "board_id" => home_board.id, "status" => "todo")
    )

    get "/api/v1/boards/#{review_board.id}/workflow_tasks"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("workflow_tasks")).to contain_exactly(
      include("id" => task.id, "board_id" => review_board.id, "status" => "in_progress")
    )

    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { board_id: review_board.id, status: "done", position: 0 }
    }

    expect(response).to have_http_status(:ok)
    expect(task.reload).to have_attributes(status: "done", completed_at: be_present)
    expect(task.workflow_task_placements.find_by!(board: home_board).workflow_column.key).to eq("done")
    expect(task.workflow_task_placements.find_by!(board: review_board).workflow_column.key).to eq("done")
    expect(deliverable.reload).to have_attributes(status: "delivered", delivered_at: be_present)

    sign_out manager
    sign_in client_user
    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("summary", "delivered_count")).to eq(1)
    expect(response.parsed_body.dig("deliverables", 0)).to include("status" => "delivered", "can_request_changes" => true)
  end

  it "does not expose a restricted secondary board to an ungranted staff member" do
    review_board.update!(visibility: :restricted)
    staff = organization.users.create!(name: "Unassigned producer", email: "multi-board-staff@example.test",
                                       password: "long-enough-password", role: :production_staff)
    sign_out manager
    sign_in staff

    get "/api/v1/boards/#{review_board.id}/workflow_tasks"

    expect(response).to have_http_status(:not_found)
  end
end
