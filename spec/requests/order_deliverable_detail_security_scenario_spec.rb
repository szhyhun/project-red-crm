require "rails_helper"

RSpec.describe "order deliverable detail security", type: :request do
  let!(:organization) { Organization.create!(name: "Detail security agency", slug: "detail-security-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Detail security manager", email: "detail-security-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Detail security client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Detail security client user", email: "detail-security-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "4 Detail Security Street") }
  let!(:service) do
    organization.products.create!(slug: "detail-security-service", title: "Detail security photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 22_000) }
  let!(:order) do
    Orders::Creator.new(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).create!.tap do |record|
      record.update!(status: :approved, approved_at: Time.current)
    end
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }
  let!(:task) do
    organization.default_board.workflow_tasks.create!(organization:, listing:, title: "Staff-only task name", status: "todo")
  end
  let!(:task_deliverable_link) { task.workflow_task_deliverables.create!(order_deliverable: deliverable, position: 0) }
  let!(:visible_asset) do
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                     kind: :final, status: :ready, storage_key: "detail-security/visible.jpg",
                                     filename: "visible.jpg", content_type: "image/jpeg", byte_size: 5,
                                     customer_visible: true)
  end
  let!(:hidden_asset) do
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                     kind: :final, status: :ready, storage_key: "detail-security/hidden.jpg",
                                     filename: "hidden.jpg", content_type: "image/jpeg", byte_size: 5,
                                     customer_visible: false)
  end
  let!(:pending_asset) do
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                     kind: :final, status: :pending, storage_key: "detail-security/pending.jpg",
                                     filename: "pending.jpg", content_type: "image/jpeg", byte_size: 5,
                                     customer_visible: true)
  end

  it "lets staff inspect all asset processing states and workflow lineage without storage keys" do
    sign_in manager

    get "/api/v1/order_deliverables/#{deliverable.id}"

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch("order_deliverable")
    expect(payload).to include(
      "materialization_key" => deliverable.materialization_key,
      "workflow_tasks" => include(hash_including("id" => task.id, "title" => "Staff-only task name"))
    )
    expect(payload.fetch("assets").pluck("id")).to contain_exactly(visible_asset.id, hidden_asset.id, pending_asset.id)
    expect(payload.fetch("assets").find { |asset| asset.fetch("id") == visible_asset.id }).to include(
      "preview_path" => "/api/v1/media_assets/#{visible_asset.id}/preview",
      "download_path" => "/api/v1/media_assets/#{visible_asset.id}/download"
    )
    expect(payload.fetch("assets").any? { |asset| asset.key?("storage_key") }).to be(false)
  end

  it "returns only customer-safe delivered assets and omits workflow internals to a customer" do
    sign_in client_user

    get "/api/v1/order_deliverables/#{deliverable.id}"

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch("order_deliverable")
    expect(payload.fetch("assets").pluck("id")).to eq([ visible_asset.id ])
    expect(payload).not_to have_key("metadata")
    expect(payload).not_to have_key("materialization_key")
    expect(payload).not_to have_key("workflow_tasks")
    expect(payload.fetch("assets").sole).to include(
      "preview_path" => "/api/v1/media_assets/#{visible_asset.id}/preview",
      "download_path" => "/api/v1/media_assets/#{visible_asset.id}/download"
    )
  end

  it "omits order and workflow lineage from the customer listing serializer" do
    sign_in manager

    get "/api/v1/listings/#{listing.id}"

    expect(response).to have_http_status(:ok)
    staff_deliverable = response.parsed_body.fetch("listing").fetch("order_deliverables").sole
    expect(staff_deliverable).to include("order_id" => order.id, "task_ids" => [ task.id ])

    sign_in client_user

    get "/api/v1/listings/#{listing.id}"

    expect(response).to have_http_status(:ok)
    customer_deliverable = response.parsed_body.fetch("listing").fetch("order_deliverables").sole
    expect(customer_deliverable).to include(
      "id" => deliverable.id,
      "title" => deliverable.title,
      "status" => deliverable.status,
      "asset_count" => 1
    )
    expect(customer_deliverable).not_to have_key("order_id")
    expect(customer_deliverable).not_to have_key("task_ids")
    expect(customer_deliverable).not_to have_key("service_product_id")
  end

  it "keeps workflow lineage out of customer order and deliverable list responses" do
    sign_in client_user

    get "/api/v1/orders/#{order.id}"

    expect(response).to have_http_status(:ok)
    order_deliverable = response.parsed_body.fetch("order").fetch("deliverables").sole
    expect(order_deliverable).to include("id" => deliverable.id, "asset_count" => 1)
    expect(order_deliverable).not_to have_key("task_ids")
    expect(order_deliverable).not_to have_key("service_product")

    get "/api/v1/orders/#{order.id}/deliverables"

    expect(response).to have_http_status(:ok)
    list_deliverable = response.parsed_body.fetch("order_deliverables").sole
    expect(list_deliverable).to include("id" => deliverable.id, "asset_count" => 1)
    expect(list_deliverable).not_to have_key("metadata")
    expect(list_deliverable).not_to have_key("order_id")
    expect(list_deliverable).not_to have_key("service_product_id")
  end

  it "does not allow a customer to update a deliverable through the staff endpoint" do
    sign_in client_user

    patch "/api/v1/order_deliverables/#{deliverable.id}", params: {
      order_deliverable: { status: "delivered", metadata: { leaked: true } }
    }

    expect(response).to have_http_status(:forbidden)
    expect(deliverable.reload).to have_attributes(status: "not_started", metadata: { "quantity" => 1 })
  end
end
