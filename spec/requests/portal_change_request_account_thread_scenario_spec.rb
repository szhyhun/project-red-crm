require "rails_helper"
require "tempfile"

RSpec.describe "Portal change request account thread scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Account thread agency", slug: "account-thread-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Account thread manager", email: "account-thread-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Account thread client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Account thread customer", email: "account-thread-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "110 Account Thread Street") }
  let!(:service) do
    organization.products.create!(slug: "account-thread-service", title: "Account thread photography", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 30_000) }
  let!(:order) do
    Orders::Create.call(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).fetch(:order).tap { |record| record.update!(status: :approved, approved_at: Time.current) }
  end
  let!(:deliverable) do
    Orders::DeliverableMaterializer.new(order:).call.sole.tap do |record|
      record.update!(status: :delivered, delivered_at: Time.current)
    end
  end
  let!(:asset) do
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                     kind: :final, status: :ready, storage_key: "account-thread/visible.jpg",
                                     filename: "visible.jpg", content_type: "image/jpeg", byte_size: 5,
                                     customer_visible: true)
  end

  before do
    allow(Conversations::NotifyJob).to receive(:perform_later)
    allow(ConversationStorage).to receive(:write)
    sign_in client_user
  end

  it "links selected delivered assets and new chat attachments into one account conversation" do
    post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
      change_request: { body: "Please replace this photo.", media_asset_ids: [ asset.id ] }
    }

    expect(response).to have_http_status(:created)
    conversation_id = response.parsed_body.dig("change_request", "conversation_id")
    change_request_message_id = response.parsed_body.dig("change_request", "message_id")
    conversation = Conversation.find(conversation_id)

    upload = Tempfile.new([ "account-thread", ".jpg" ])
    upload.write("new customer reference")
    upload.rewind
    post "/api/v1/conversations/#{conversation.id}/messages", params: {
      message: { body: "Here is another reference." }
    }
    expect(response).to have_http_status(:created)
    message_id = response.parsed_body.dig("message", "id")

    post "/api/v1/conversations/#{conversation.id}/messages/#{message_id}/attachments", params: {
      files: [ Rack::Test::UploadedFile.new(upload.path, "image/jpeg", true, original_filename: "reference.jpg") ]
    }
    expect(response).to have_http_status(:created)

    expect(conversation.reload.messages.order(:created_at).pluck(:id)).to contain_exactly(
      change_request_message_id, message_id
    )
    expect(Message.find(change_request_message_id).message_media_references.sole.media_asset).to eq(asset)
    attachment = Message.find(message_id).conversation_attachments.sole
    expect(attachment).to have_attributes(filename: "reference.jpg", status: "ready")
    expect(response.parsed_body.fetch("conversation_attachments").sole.keys).not_to include("storage_key")
  ensure
    upload&.close!
  end
end
