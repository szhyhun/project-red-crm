require "rails_helper"

RSpec.describe "Conversation context chips API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Context chip agency", slug: "context-chip-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Context chip manager", email: "context-chip-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Context chip client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Context chip customer", email: "context-chip-customer@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "12 Context Chip Street") }
  let!(:service) do
    organization.products.create!(slug: "context-chip-photo", title: "Standard Property Photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 25_000) }
  let!(:order) do
    Orders::Creator.new(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).create!.tap { |record| record.update!(status: :approved, approved_at: Time.current) }
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }
  let!(:asset) do
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                     kind: :final, status: :ready, storage_key: "context-chip/front.jpg",
                                     filename: "front.jpg", content_type: "image/jpeg", byte_size: 5,
                                     customer_visible: true)
  end
  let!(:conversation) do
    Conversation.account_thread_for(organization:, client_account:).tap do |record|
      record.conversation_memberships.create!(user: manager, role: :manager)
      record.conversation_memberships.create!(user: client_user, role: :participant)
    end
  end

  before do
    allow(Conversations::NotifyJob).to receive(:perform_later)
    sign_in manager
  end

  it "serializes human-readable listing, service, and selected-asset context for staff" do
    post "/api/v1/conversations/#{conversation.id}/messages", params: {
      message: {
        body: "Please replace this exterior photo.", listing_id: listing.id,
        order_deliverable_id: deliverable.id, media_asset_ids: [ asset.id ]
      }
    }

    expect(response).to have_http_status(:created)
    serialized = response.parsed_body.fetch("message")
    expect(serialized.fetch("context")).to eq(
      "listing" => { "id" => listing.id, "address" => listing.address },
      "deliverable" => {
        "id" => deliverable.id, "title" => "Standard Property Photography", "deliverable_type" => "photography"
      },
      "selected_asset_count" => 1
    )
  end

  it "keeps the same context when the customer reads the account conversation" do
    message = conversation.messages.create!(author: manager, body: "The photography delivery is ready.",
                                            listing:, order_deliverable: deliverable)
    message.message_media_references.create!(media_asset: asset, position: 0)

    sign_out manager
    sign_in client_user
    get "/api/v1/portal/dashboard"

    expect(response).to have_http_status(:ok)
    portal_message = response.parsed_body.fetch("conversations").sole.fetch("messages").sole
    expect(portal_message).to include(
      "message_kind" => "message", "listing_id" => listing.id, "order_deliverable_id" => deliverable.id
    )
    expect(portal_message.fetch("context")).to include(
      "listing" => { "id" => listing.id, "address" => listing.address },
      "deliverable" => hash_including("id" => deliverable.id, "title" => deliverable.title),
      "selected_asset_count" => 1
    )
    expect(portal_message).not_to have_key("storage_key")
  end

  it "does not manufacture a context chip for an ordinary message" do
    post "/api/v1/conversations/#{conversation.id}/messages", params: {
      message: { body: "General production update." }
    }

    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch("message")).to include("context" => nil)
  end
end
