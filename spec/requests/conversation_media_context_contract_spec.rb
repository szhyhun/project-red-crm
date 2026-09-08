require "rails_helper"

RSpec.describe "Conversation media context contract", type: :request do
  let!(:organization) { Organization.create!(name: "Conversation context agency", slug: "conversation-context") }
  let!(:manager) do
    User.create!(organization:, name: "Context manager", email: "conversation-context-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_user) do
    User.create!(organization:, name: "Context client", email: "conversation-context-client@example.test",
                 password: "long-enough-password", role: :client_admin)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Context account", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "3 Context Street") }
  let!(:service) do
    organization.products.create!(slug: "context-service", title: "Context photography", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 18_000) }
  let!(:order) do
    Orders::Creator.new(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).create!
  end
  let!(:deliverable) do
    Orders::Approval.new(order:, actor: manager).call
    order.reload.order_deliverables.sole
  end
  let!(:asset) do
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                     kind: :final, status: :ready, storage_key: "private/context.jpg",
                                     filename: "context.jpg", content_type: "image/jpeg", byte_size: 5,
                                     customer_visible: true)
  end
  let!(:conversation) do
    Conversation.account_thread_for(organization:, client_account:).tap do |record|
      record.conversation_memberships.find_or_create_by!(user: manager) { |membership| membership.role = :manager }
      record.conversation_memberships.find_or_create_by!(user: client_user) { |membership| membership.role = :participant }
    end
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    ClientMembership.create!(client_account:, user: client_user, role: :admin)
    sign_in manager
  end

  it "references an existing asset without copying it into chat" do
    expect {
      post "/api/v1/conversations/#{conversation.id}/messages", params: {
        message: { body: "Please use this photo", listing_id: listing.id,
                    order_deliverable_id: deliverable.id, media_asset_ids: [ asset.id ] }
      }
    }.to change(Message, :count).by(1).and change(MessageMediaReference, :count).by(1)

    expect(response).to have_http_status(:created)
    serialized = response.parsed_body.fetch("message")
    expect(serialized).to include("listing_id" => listing.id, "order_deliverable_id" => deliverable.id)
    expect(serialized.fetch("media_references").sole).to include(
      "id" => asset.id,
      "preview_path" => "/api/v1/media_assets/#{asset.id}/preview",
      "download_path" => "/api/v1/media_assets/#{asset.id}/download"
    )
    expect(serialized.fetch("media_references").sole).not_to have_key("storage_key")
    expect(asset.reload).to have_attributes(order_deliverable_id: deliverable.id)
  end

  it "rejects a customer reference to hidden media from the same listing" do
    hidden = deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                              kind: :final, status: :ready, storage_key: "private/hidden.jpg",
                                              filename: "hidden.jpg", content_type: "image/jpeg", byte_size: 5,
                                              customer_visible: false)
    sign_out manager
    sign_in client_user

    expect {
      post "/api/v1/conversations/#{conversation.id}/messages", params: {
        message: { body: "I should not reference this", listing_id: listing.id,
                    order_deliverable_id: deliverable.id, media_asset_ids: [ hidden.id ] }
      }
    }.not_to change(Message, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "rolls back the whole message when the selected asset belongs to another deliverable" do
    other_service = organization.products.create!(slug: "context-video", title: "Context video", kind: :service,
                                                   deliverable_type: "video")
    other_variant = other_service.product_variants.create!(title: "Standard", price_cents: 22_000)
    other_order = Orders::Creator.new(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: other_variant.id, quantity: 1 } ]
    }).create!
    other_deliverable = Orders::Approval.new(order: other_order, actor: manager).call.order_deliverables.sole
    foreign_asset = other_deliverable.media_assets.create!(organization:, listing:, order: other_order,
                                                            order_item: other_order.order_items.sole, kind: :final,
                                                            status: :ready, storage_key: "private/other.jpg",
                                                            filename: "other.jpg", content_type: "image/jpeg", byte_size: 5,
                                                            customer_visible: true)

    expect {
      post "/api/v1/conversations/#{conversation.id}/messages", params: {
        message: { body: "Wrong deliverable", listing_id: listing.id,
                    order_deliverable_id: deliverable.id, media_asset_ids: [ foreign_asset.id ] }
      }
    }.not_to change(Message, :count)

    expect(response).to have_http_status(:not_found)
    expect(MessageMediaReference.where(media_asset: foreign_asset)).to be_empty
  end
end
