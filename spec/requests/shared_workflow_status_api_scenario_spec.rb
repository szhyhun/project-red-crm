require "rails_helper"

RSpec.describe "Shared workflow status API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Shared status agency", slug: "shared-status-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Shared status manager", email: "shared-status@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Shared status client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "20 Shared Status Street") }
  let!(:home_board) { organization.default_board }
  let!(:shared_board) do
    organization.boards.create!(name: "Review board", kind: :internal, visibility: :organization,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
      board.workflow_columns.create!(organization:, key: "review", name: "Review", color: "#c9b6ff",
                                     category: :active, position: 4)
    end
  end
  let!(:service) do
    organization.products.create!(slug: "shared-status-service", title: "Shared status photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:order) do
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                  status: :approved, approved_at: Time.current).tap do |record|
      record.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                                 unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
    end
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }
  let!(:task) do
    home_board.workflow_tasks.create!(organization:, listing:, title: "Review the finished photos", status: "todo").tap do |record|
      record.workflow_task_deliverables.create!(order_deliverable: deliverable, position: 0)
      record.workflow_task_placements.create!(board: shared_board,
                                              workflow_column: shared_board.workflow_columns.find_by!(key: "todo"),
                                              position: 0, is_home: false)
    end
  end

  before { sign_in manager }

  it "updates the canonical deliverable and every board placement when moved from a shared board" do
    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { board_id: shared_board.id, status: "review", position: 0 }
    }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("workflow_task")).to include(
      "board_id" => shared_board.id,
      "status" => "review",
      "placement_id" => task.workflow_task_placements.find_by!(board: shared_board).id
    )
    expect(task.reload).to have_attributes(status: "in_progress")
    expect(task.workflow_task_placements.find_by!(board: home_board).workflow_column.key).to eq("in_progress")
    expect(task.workflow_task_placements.find_by!(board: shared_board).workflow_column.key).to eq("review")
    expect(deliverable.reload).to have_attributes(status: "in_review", delivered_at: nil)
    expect(deliverable.activity_events.where(event_type: "order_deliverable.status_changed")).to exist
  end

  it "returns the shared placement instead of the home card when that board is requested" do
    get "/api/v1/boards/#{shared_board.id}/workflow_tasks"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("workflow_tasks")).to contain_exactly(
      include("id" => task.id, "board_id" => shared_board.id,
              "workflow_column_id" => shared_board.workflow_columns.find_by!(key: "todo").id,
              "placement_id" => task.workflow_task_placements.find_by!(board: shared_board).id)
    )
  end
end
