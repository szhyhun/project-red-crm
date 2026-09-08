require "rails_helper"

RSpec.describe "Standalone media workflow scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Standalone Agency", slug: "standalone-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Standalone Manager", email: "standalone-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Standalone Client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Standalone Client User", email: "standalone-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "18 Standalone Street") }
  let!(:service) do
    organization.products.create!(slug: "standalone-photography", title: "Standard property photography",
                                  kind: :service, deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) do
    service.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 29_900, sqft_min: 0, sqft_max: 1_000)
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    sign_in manager
  end

  it "sells one service, invoices that service once, and creates linked production work" do
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
    invoice = Invoices::Creator.new(organization:, order:).create!

    expect(order.reload).to have_attributes(status: "invoiced", subtotal_cents: 29_900, total_cents: 29_900)
    expect(invoice).to have_attributes(subtotal_cents: 29_900, total_cents: 29_900, balance_due_cents: 29_900)
    expect(order.order_items.count).to eq(1)
    expect(order.order_deliverables.count).to eq(1)
    expect(deliverable).to have_attributes(
      service_product: service,
      product_component: nil,
      scope_label: "0–1,000 sqft"
    )

    child_task = WorkflowTask.where(organization:, task_kind: "deliverable").sole
    expect(child_task.order_deliverables).to contain_exactly(deliverable)
    expect(child_task.home_placement.workflow_column.key).to eq("todo")

    get "/api/v1/orders/#{order.id}/deliverables"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("order_deliverables").sole).to include(
      "id" => deliverable.id,
      "scope_label" => "0–1,000 sqft",
      "asset_count" => 0
    )
  end
end
