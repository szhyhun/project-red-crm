require "rails_helper"

RSpec.describe "Staff deliverable workflow contract", type: :request do
  let!(:organization) { Organization.create!(name: "Staff deliverable contract agency", slug: "staff-deliverable-contract") }
  let!(:manager) do
    User.create!(organization:, name: "Staff contract manager", email: "staff-contract-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Staff contract client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "70 Staff Contract Street") }
  let!(:service) do
    organization.products.create!(slug: "staff-contract-service", title: "Standard property photography",
                                  kind: :service, deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 32_000) }
  let!(:order) do
    Orders::Create.call(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).fetch(:order).tap { |record| record.update!(status: :approved, approved_at: Time.current) }
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }
  let!(:task) do
    organization.default_board.workflow_tasks.create!(organization:, listing:, title: "Prepare final photos",
                                                       status: "in_progress")
  end
  let!(:task_link) { task.workflow_task_deliverables.create!(order_deliverable: deliverable, position: 0) }

  before { sign_in manager }

  it "includes linked workflow task information in the staff collection response" do
    get "/api/v1/orders/#{order.id}/deliverables"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("order_deliverables").sole).to include(
      "id" => deliverable.id,
      "workflow_tasks" => contain_exactly(
        include("id" => task.id, "title" => "Prepare final photos", "status" => "in_progress")
      )
    )
  end

  it "keeps workflow lineage out of the customer deliverable response" do
    client_user = User.create!(organization:, name: "Staff contract customer", email: "staff-contract-client@example.test",
                               password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account:, user: client_user, role: :admin)
    sign_out manager
    sign_in client_user

    get "/api/v1/order_deliverables/#{deliverable.id}"

    expect(response).to have_http_status(:ok)
    customer_payload = response.parsed_body.fetch("order_deliverable")
    expect(customer_payload).not_to have_key("workflow_tasks")
    expect(customer_payload).not_to have_key("materialization_key")
    expect(customer_payload).not_to have_key("order_id")
  end
end
