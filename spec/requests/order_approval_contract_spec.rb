require "rails_helper"

RSpec.describe "Order approval contract", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Approval contract agency", slug: "approval-contract") }
  let!(:other_organization) { Organization.create!(name: "Other approval agency", slug: "other-approval-contract") }
  let!(:manager) do
    User.create!(organization:, name: "Approval manager", email: "approval-contract-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_user) do
    User.create!(organization:, name: "Approval client", email: "approval-contract-client@example.test",
                 password: "long-enough-password", role: :client_admin)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Approval client account", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "2 Approval Street") }
  let!(:service) do
    organization.products.create!(slug: "approval-service", title: "Approval photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) do
    service.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 24_900, sqft_min: 0, sqft_max: 1_000)
  end
  let!(:order) do
    Orders::Creator.new(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).create!
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    ClientMembership.create!(client_account:, user: client_user, role: :admin)
    sign_in manager
  end

  it "approves through the canonical endpoint and returns linked deliverables" do
    expect {
      post "/api/v1/orders/#{order.id}/approve"
    }.to change { order.reload.order_deliverables.count }.from(0).to(1)
      .and change(BoardWorkflowRun, :count).by(1)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch("order")
    expect(payload).to include("status" => "approved")
    expect(payload.fetch("approved_at")).to be_present
    expect(payload.fetch("deliverables").sole).to include(
      "service_product" => hash_including("id" => service.id),
      "scope_label" => "0–1,000 sqft"
    )
  end

  it "preserves the original order price when the catalog variant changes before approval" do
    variant.update!(price_cents: 99_900)

    post "/api/v1/orders/#{order.id}/approve"

    expect(response).to have_http_status(:ok)
    expect(order.reload.order_items.sole).to have_attributes(unit_price_cents: 24_900, total_cents: 24_900)
    expect(order.total_cents).to eq(24_900)
  end

  it "does not let a customer approve an order" do
    sign_out manager
    sign_in client_user

    post "/api/v1/orders/#{order.id}/approve"

    expect(response).to have_http_status(:forbidden)
    expect(order.reload).not_to be_approved
    expect(order.order_deliverables).to be_empty
  end

  it "does not resolve another organization's order through the endpoint" do
    other_client = ClientAccount.create!(organization: other_organization, name: "Other approval client", kind: :agent)
    other_order = Order.create!(organization: other_organization, client_account: other_client, payment_mode: :pay_later)

    post "/api/v1/orders/#{other_order.id}/approve"

    expect(response).to have_http_status(:not_found)
    expect(other_order.reload).not_to be_approved
  end

  it "requeues an unfinished workflow run after an earlier approval committed" do
    post "/api/v1/orders/#{order.id}/approve"
    expect(response).to have_http_status(:ok)
    clear_enqueued_jobs

    post "/api/v1/orders/#{order.id}/approve"

    expect(response).to have_http_status(:ok)
    expect(order.reload.order_deliverables.count).to eq(1)
    expect(BoardWorkflowRun.where(order: order).count).to eq(1)
    expect(enqueued_jobs.map { |job| job[:job] }).to include(BoardWorkflowJob)
  end
end
