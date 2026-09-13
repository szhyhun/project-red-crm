require "rails_helper"

RSpec.describe "Customer listing API boundary scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Listing boundary agency", slug: "listing-boundary-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Listing boundary manager", email: "listing-boundary-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Visible boundary client", kind: :agent) }
  let!(:other_account) { ClientAccount.create!(organization:, name: "Other boundary client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Listing boundary customer", email: "listing-boundary-customer@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "3 Listing Boundary Street") }
  let!(:service) do
    organization.products.create!(slug: "listing-boundary-service", title: "Boundary photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 18_000) }
  let!(:order) do
    Orders::Create.call(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).fetch(:order).tap do |record|
      record.update_columns(status: "approved", approved_at: Time.current)
    end
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }
  let!(:customer_task) do
    organization.default_board.workflow_tasks.create!(organization:, listing:, title: "Visible progress", status: "todo",
                                                       customer_visible: true)
  end
  let!(:staff_task) do
    organization.default_board.workflow_tasks.create!(organization:, listing:, title: "Private QA notes", status: "todo",
                                                       customer_visible: false)
  end

  before { sign_in client_user }

  it "returns a customer-safe listing detail without staff associations or lineage" do
    listing.listing_customers.create!(client_account: other_account)
    Appointment.create!(organization:, listing:, starts_at: 2.days.from_now, ends_at: 2.days.from_now + 1.hour,
                        assigned_user: manager, notes: "Internal scheduling note")

    get "/api/v1/listings/#{listing.id}"

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch("listing")
    expect(payload).to include(
      "id" => listing.id,
      "address" => "3 Listing Boundary Street",
      "status" => "scheduled",
      "order_deliverables" => include(hash_including("id" => deliverable.id, "asset_count" => 0)),
      "workflow_tasks" => include(hash_including("id" => customer_task.id, "title" => "Visible progress"))
    )
    expect(payload.fetch("workflow_tasks").pluck("id")).not_to include(staff_task.id)
    expect(payload).not_to include(
      "client_account", "listing_customers", "appointment", "assigned_team_member", "order",
      "payment_status", "feedback_summary", "cover_image_url"
    )
    safe_deliverable = payload.fetch("order_deliverables").sole
    expect(safe_deliverable).not_to include("order_id", "service_product_id", "task_ids", "metadata")
  end

  it "does not expose organization-wide filter choices to a customer" do
    organization.products.create!(slug: "private-filter-product", title: "Private catalog product", kind: :service)
    listing.update!(tags: [ "private-customer-tag" ])

    get "/api/v1/listings"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("listings").pluck("id")).to eq([ listing.id ])
    expect(response.parsed_body.fetch("filter_options")).to eq(
      "products" => [], "tags" => [], "team_members" => []
    )
  end
end
