require "rails_helper"

RSpec.describe "conversation message contract API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Message contract agency", slug: "message-contract-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Message contract manager", email: "message-contract-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Message contract client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Message contract customer", email: "message-contract-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:outsider) do
    User.create!(organization:, name: "Message contract outsider", email: "message-contract-outsider@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "5 Message Contract Street") }
  let!(:service) do
    organization.products.create!(slug: "message-contract-service", title: "Message contract photography",
                                  kind: :service, deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:order) do
    Orders::Creator.new(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).create!.tap do |record|
      record.update!(status: :approved, approved_at: Time.current)
    end
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole }
  let!(:visible_asset) do
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                     kind: :final, status: :ready, storage_key: "message-contract/visible.jpg",
                                     filename: "visible.jpg", content_type: "image/jpeg", byte_size: 5,
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
    sign_in client_user
  end

  it "accepts rich text and returns the sanitized plain-text message" do
    post "/api/v1/conversations/#{conversation.id}/messages", params: {
      message: {
        body_html: '<p>Keep this line.</p><script>alert("remove")</script><a href="javascript:bad">link</a>'
      }
    }

    expect(response).to have_http_status(:created)
    message = Message.find(response.parsed_body.dig("message", "id"))
    expect(message.body).to eq("Keep this line.\nlink")
    expect(message.body_html).not_to include("<script", "javascript:")
    expect(response.parsed_body.dig("message", "body")).to eq("Keep this line.\nlink")
  end

  it "returns a validation response instead of a server error for an empty message" do
    expect {
      post "/api/v1/conversations/#{conversation.id}/messages", params: {
        message: { body: "", body_html: "<p> </p>" }
      }
    }.not_to change(Message, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include("error" => "validation_failed")
    expect(response.parsed_body.dig("details", "body")).to include("can't be blank")
  end

  it "stores listing and deliverable context and serializes referenced media with API paths" do
    post "/api/v1/conversations/#{conversation.id}/messages", params: {
      message: {
        body: "Please use this photo as the reference.",
        listing_id: listing.id,
        order_deliverable_id: deliverable.id,
        media_asset_ids: [ visible_asset.id ]
      }
    }

    expect(response).to have_http_status(:created)
    message = Message.find(response.parsed_body.dig("message", "id"))
    reference = message.message_media_references.sole
    serialized = response.parsed_body.fetch("message")

    expect(message).to have_attributes(listing:, order_deliverable: deliverable, author: client_user)
    expect(reference.media_asset).to eq(visible_asset)
    expect(serialized.fetch("media_references")).to contain_exactly(
      hash_including(
        "id" => visible_asset.id,
        "preview_path" => "/api/v1/media_assets/#{visible_asset.id}/preview",
        "download_path" => "/api/v1/media_assets/#{visible_asset.id}/download"
      )
    )
    expect(serialized).not_to have_key("storage_key")
    expect(Conversations::NotifyJob).to have_received(:perform_later).with(message.id)
  end

  it "does not let a customer post context for a different listing" do
    foreign_account = ClientAccount.create!(organization:, name: "Other message account", kind: :agent)
    foreign_listing = Listing.create!(organization:, client_account: foreign_account,
                                      address_line_1: "6 Private Message Street")

    expect {
      post "/api/v1/conversations/#{conversation.id}/messages", params: {
        message: { body: "Wrong context", listing_id: foreign_listing.id }
      }
    }.not_to change(Message, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "does not let a non-member read or post to the account conversation" do
    sign_out client_user
    sign_in outsider

    get "/api/v1/conversations/#{conversation.id}"
    expect(response).to have_http_status(:not_found)

    post "/api/v1/conversations/#{conversation.id}/messages", params: {
      message: { body: "I should not be here" }
    }
    expect(response).to have_http_status(:not_found)
    expect(conversation.messages).to be_empty
  end
end
