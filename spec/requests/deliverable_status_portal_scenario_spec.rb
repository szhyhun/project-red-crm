require "rails_helper"

RSpec.describe "Deliverable status and portal scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Status portal agency", slug: "status-portal-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Status portal manager", email: "status-portal-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Status portal client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Status portal customer", email: "status-portal-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "10 Status Portal Street") }
  let!(:service) do
    organization.products.create!(slug: "status-portal-service", title: "Standard property photography",
                                  kind: :service, deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 30_000) }
  let!(:order) do
    Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later, status: :approved,
                  approved_at: Time.current).tap do |record|
      record.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                                 unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
    end
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }
  let!(:board) { organization.default_board }
  let!(:review_column) do
    board.workflow_columns.create!(organization:, key: "review", name: "Review", color: "#c9b6ff",
                                   category: :active, position: 4)
  end
  let!(:task) do
    board.workflow_tasks.create!(organization:, listing:, title: "Prepare the delivered photos", status: "todo").tap do |record|
      record.workflow_task_deliverables.create!(order_deliverable: deliverable, position: 0)
    end
  end

  before { sign_in manager }

  it "carries task movement through every customer-facing delivery state" do
    {
      "in_progress" => [ "in_progress", false ],
      "review" => [ "in_review", false ],
      "done" => [ "delivered", true ]
    }.each do |task_status, (deliverable_status, can_request_changes)|
      patch "/api/v1/workflow_tasks/#{task.id}", params: {
        workflow_task: { status: task_status, position: 0 }
      }

      expect(response).to have_http_status(:ok)
      expect(deliverable.reload).to have_attributes(status: deliverable_status)
      expect(deliverable.delivered_at).to be_present if deliverable_status == "delivered"

      sign_out manager
      sign_in client_user
      get "/api/v1/portal/listings/#{listing.id}/media"

      expect(response).to have_http_status(:ok)
      portal_deliverable = response.parsed_body.fetch("deliverables").sole
      expect(portal_deliverable).to include(
        "status" => deliverable_status,
        "can_request_changes" => can_request_changes
      )

      sign_out client_user
      sign_in manager
    end

    expect(deliverable.activity_events.where(event_type: "order_deliverable.status_changed").count).to eq(3)
  end

  it "rejects a move to a missing board column without changing production state" do
    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { status: "not_a_real_column", position: 0 }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "status")).to include("must match a column on this board")
    expect(task.reload).to have_attributes(status: "todo")
    expect(deliverable.reload).to have_attributes(status: "not_started", delivered_at: nil)
    expect(deliverable.activity_events.where(event_type: "order_deliverable.status_changed")).to be_empty
  end
end
