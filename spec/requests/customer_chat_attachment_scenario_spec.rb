require "rails_helper"
require "tempfile"

RSpec.describe "Customer chat attachment API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Customer chat agency", slug: "customer-chat-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Customer chat manager", email: "customer-chat-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Customer chat account", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Customer chat user", email: "customer-chat-user@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:conversation) do
    Conversation.account_thread_for(organization:, client_account:).tap do |record|
      record.conversation_memberships.find_or_create_by!(user: manager) { |membership| membership.role = :manager }
      record.conversation_memberships.find_or_create_by!(user: client_user) { |membership| membership.role = :participant }
    end
  end

  before do
    allow(Conversations::NotifyJob).to receive(:perform_later)
    allow(ConversationStorage).to receive(:write)
    sign_in client_user
  end

  it "lets a customer send a message, attach a file, and reopen it through API-relative routes" do
    post "/api/v1/conversations/#{conversation.id}/messages", params: {
      message: { body: "Here is the reference photo." }
    }
    expect(response).to have_http_status(:created)
    message = Message.find(response.parsed_body.dig("message", "id"))

    upload = Tempfile.new([ "customer-chat", ".jpg" ])
    upload.write("image bytes")
    upload.rewind
    post "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments", params: {
      files: [ Rack::Test::UploadedFile.new(upload.path, "image/jpeg", true, original_filename: "reference.jpg") ]
    }

    expect(response).to have_http_status(:created)
    attachment = message.conversation_attachments.sole
    serialized = response.parsed_body.fetch("conversation_attachments").sole
    expect(serialized).to include(
      "id" => attachment.id,
      "preview_path" => "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{attachment.id}/preview",
      "download_path" => "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{attachment.id}/download"
    )
    expect(serialized).not_to have_key("storage_key")

    get "/api/v1/conversations/#{conversation.id}"

    expect(response).to have_http_status(:ok)
    reopened = response.parsed_body.dig("conversation", "messages").sole
    expect(reopened.fetch("attachments")).to contain_exactly(hash_including("id" => attachment.id,
                                                                                "filename" => "reference.jpg"))
    expect(Conversations::NotifyJob).to have_received(:perform_later).with(message.id)
  ensure
    upload&.close!
  end

  it "keeps a customer attachment inside the account conversation boundary" do
    message = conversation.messages.create!(author: client_user, body: "Private customer file")
    attachment = conversation.conversation_attachments.create!(organization:, message:, uploaded_by: client_user,
                                                                status: :ready,
                                                                storage_key: "organizations/#{organization.id}/conversations/#{conversation.id}/private.jpg",
                                                                filename: "private.jpg", content_type: "image/jpeg",
                                                                byte_size: 5)
    other_account = ClientAccount.create!(organization:, name: "Other customer account", kind: :agent)
    other_user = User.create!(organization:, name: "Other customer", email: "other-customer-chat@example.test",
                              password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: other_account, user: other_user, role: :admin)
    sign_out client_user
    sign_in other_user

    get "/api/v1/conversations/#{conversation.id}"
    expect(response).to have_http_status(:not_found)

    get "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{attachment.id}/download"
    expect(response).to have_http_status(:not_found)
  end

  it "rolls back a message with a context asset from another customer account" do
    other_account = ClientAccount.create!(organization:, name: "Foreign context account", kind: :agent)
    other_listing = Listing.create!(organization:, client_account: other_account, address_line_1: "90 Private Chat Street")
    asset = MediaAsset.create!(organization:, listing: other_listing, kind: :final, status: :ready,
                               storage_key: "customer-chat/foreign.jpg", filename: "foreign.jpg",
                               content_type: "image/jpeg", customer_visible: true)

    expect {
      post "/api/v1/conversations/#{conversation.id}/messages", params: {
        message: { body: "I should not reference that", media_asset_ids: [ asset.id ] }
      }
    }.not_to change(Message, :count)

    expect(response).to have_http_status(:not_found)
    expect(MessageMediaReference.where(media_asset: asset)).to be_empty
  end
end
