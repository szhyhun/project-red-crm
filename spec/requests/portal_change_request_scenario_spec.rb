require "rails_helper"

RSpec.describe "Portal change request API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Change request agency", slug: "change-request-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Change request manager", email: "change-request-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Change request client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Change request client user", email: "change-request-client@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "40 Change Request Street") }
  let!(:service) do
    organization.products.create!(slug: "change-request-service", title: "Standard property photography",
                                  kind: :service, deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 30_000) }
  let!(:order) do
    Orders::Create.call(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).fetch(:order)
  end
  let!(:deliverable) do
    order.update!(status: :approved, approved_at: Time.current)
    Orders::DeliverableMaterializer.new(order:).call.sole.tap do |record|
      record.update!(status: :delivered, delivered_at: Time.current)
    end
  end
  let!(:visible_asset) do
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                     kind: :final, status: :ready, category: :images,
                                     storage_key: "change-requests/visible.jpg", filename: "front.jpg",
                                     content_type: "image/jpeg", byte_size: 5, customer_visible: true)
  end

  before do
    allow(Conversations::NotifyJob).to receive(:perform_later)
    sign_in client_user
  end

  it "creates a contextual message, references selected media, and reopens the deliverable" do
    expect {
      post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
        change_request: {
          body: "Please replace the exterior photo.",
          body_html: "<p>Please replace the exterior photo.</p>",
          media_asset_ids: [ visible_asset.id ]
        }
      }
    }.to change(Message, :count).by(1)
      .and change(MessageMediaReference, :count).by(1)
      .and change(ActivityEvent, :count).by(2)

    expect(response).to have_http_status(:created)
    payload = response.parsed_body.fetch("change_request")
    message = Message.find(payload.fetch("message_id"))

    expect(message).to have_attributes(
      conversation_id: payload.fetch("conversation_id"),
      author: client_user,
      body: "Please replace the exterior photo.",
      message_kind: "change_request",
      listing_id: listing.id,
      order_deliverable_id: deliverable.id
    )
    expect(message.message_media_references.sole.media_asset).to eq(visible_asset)
    expect(message.conversation).to have_attributes(client_account:, listing: nil)
    expect(deliverable.reload).to have_attributes(status: "in_progress", delivered_at: nil)
    expect(payload.dig("deliverable", "status")).to eq("in_progress")
    expect(payload.dig("deliverable", "can_request_changes")).to be(false)
    expect(Conversations::NotifyJob).to have_received(:perform_later).with(message.id)
  end

  it "sanitizes rich text before storing the plain-text message body" do
    post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
      change_request: {
        body_html: '<p>Keep this</p><script>alert("x")</script><a href="javascript:bad">bad</a>'
      }
    }

    expect(response).to have_http_status(:created)
    message = Message.find(response.parsed_body.dig("change_request", "message_id"))
    expect(message.body).to eq("Keep this\nbad")
    expect(message.body_html).not_to include("<script", "javascript:")
  end

  it "rejects a request without a message and leaves delivered work unchanged" do
    expect {
      post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
        change_request: { body: "", body_html: "<p> </p>" }
      }
    }.not_to change(Message, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to eq("message_required")
    expect(deliverable.reload).to be_delivered
  end

  it "rejects a selected asset that is not customer-visible" do
    hidden_asset = deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                                     kind: :final, status: :ready, category: :images,
                                                     storage_key: "change-requests/hidden.jpg", filename: "hidden.jpg",
                                                     content_type: "image/jpeg", byte_size: 5, customer_visible: false)

    post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
      change_request: { body: "Replace this", media_asset_ids: [ hidden_asset.id ] }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to eq("invalid_media_asset_reference")
    expect(deliverable.reload).to be_delivered
    expect(Message.where(order_deliverable_id: deliverable.id)).to be_empty
  end

  it "rejects a selected asset from another deliverable even on the same listing" do
    other_service = organization.products.create!(slug: "change-request-video", title: "Property video",
                                                   kind: :service, deliverable_type: "video")
    other_variant = other_service.product_variants.create!(title: "Standard", price_cents: 20_000)
    other_order = Orders::Create.call(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: other_variant.id, quantity: 1 } ]
    }).fetch(:order)
    other_order.update!(status: :approved, approved_at: Time.current)
    other_deliverable = Orders::DeliverableMaterializer.new(order:).call.find do |record|
      record.service_product_id == other_service.id
    end
    other_deliverable ||= Orders::DeliverableMaterializer.new(order: other_order).call.sole
    other_deliverable.update!(status: :delivered, delivered_at: Time.current)
    foreign_asset = other_deliverable.media_assets.create!(organization:, listing:, order: other_order,
                                                            order_item: other_order.order_items.sole, kind: :final,
                                                            status: :ready, category: :videos,
                                                            storage_key: "change-requests/other.mp4", filename: "other.mp4",
                                                            content_type: "video/mp4", byte_size: 5,
                                                            customer_visible: true)

    post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
      change_request: { body: "Wrong asset", media_asset_ids: [ foreign_asset.id ] }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to eq("invalid_media_asset_reference")
    expect(deliverable.reload).to be_delivered
    expect(Message.where(order_deliverable_id: deliverable.id)).to be_empty
  end

  it "does not let a customer request changes on another customer's listing" do
    other_account = ClientAccount.create!(organization:, name: "Other change request client", kind: :agent)
    other_listing = Listing.create!(organization:, client_account: other_account, address_line_1: "41 Private Street")

    expect {
      post "/api/v1/portal/listings/#{other_listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
        change_request: { body: "Not mine" }
      }
    }.not_to change(Message, :count)

    expect(response).to have_http_status(:not_found)
    expect(deliverable.reload).to be_delivered
  end

  it "returns every approved deliverable with a compact waiting state for empty work" do
    waiting_service = organization.products.create!(slug: "change-request-video", title: "Property video",
                                                     description: "A short property video.", kind: :service,
                                                     deliverable_type: "video", sla_days: 3)
    waiting_variant = waiting_service.product_variants.create!(title: "Standard", price_cents: 20_000)
    waiting_order = Orders::Create.call(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: waiting_variant.id, quantity: 1 } ]
    }).fetch(:order)
    waiting_order.update!(status: :approved, approved_at: Time.current)
    waiting_deliverable = Orders::DeliverableMaterializer.new(order: waiting_order).call.sole

    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload.fetch("deliverables").pluck("id")).to contain_exactly(deliverable.id, waiting_deliverable.id)
    waiting_payload = payload.fetch("deliverables").find { |entry| entry.fetch("id") == waiting_deliverable.id }
    expect(waiting_payload).to include(
      "title" => "Property video",
      "status" => "not_started",
      "asset_count" => 0,
      "can_request_changes" => false,
      "assets" => []
    )
    expect(waiting_payload).not_to have_key("materialization_key")
    expect(waiting_payload).not_to have_key("metadata")
  end
end
