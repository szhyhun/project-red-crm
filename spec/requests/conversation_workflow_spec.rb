require "rails_helper"

RSpec.describe "Conversation workflow API", type: :request do
  let!(:organization) { Organization.create!(name: "Conversation Workflow Agency", slug: "conversation-workflow-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Conversation Agency", slug: "other-conversation-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Conversation Manager", email: "conversation-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:producer) do
    User.create!(organization:, name: "Conversation Producer", email: "conversation-producer@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Conversation client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Conversation client user", email: "conversation-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "12 Conversation Street") }

  before { sign_in manager }

  it "creates one account-wide customer conversation even when the create action is retried" do
    params = {
      conversation: {
        kind: "client", client_account_id: client_account.id, subject: "Production updates",
        member_ids: [ producer.id ]
      }
    }

    expect {
      post "/api/v1/conversations", params: params
      expect(response).to have_http_status(:created)
      post "/api/v1/conversations", params: params
    }.to change(Conversation, :count).by(1)

    expect(response).to have_http_status(:created)
    conversation = Conversation.account_thread_for(organization:, client_account:)
    expect(conversation.reload.conversation_memberships.pluck(:user_id)).to contain_exactly(manager.id, producer.id, client_user.id)
    expect(conversation.conversation_memberships.where(user_id: manager.id).count).to eq(1)
  end

  it "rolls back a message when a referenced asset fails the context check" do
    first_listing = listing
    second_listing = Listing.create!(organization:, client_account:, address_line_1: "13 Conversation Street")
    conversation = Conversation.create!(organization:, kind: :internal, subject: "Asset context").tap do |record|
      record.conversation_memberships.create!(user: manager, role: :manager)
    end
    asset = MediaAsset.create!(organization:, listing: second_listing, kind: :final, status: :ready,
                               source_url: "https://cdn.example.test/foreign-context.jpg", filename: "foreign-context.jpg",
                               content_type: "image/jpeg", customer_visible: true)

    expect {
      post "/api/v1/conversations/#{conversation.id}/messages", params: {
        message: { body: "Wrong listing context", listing_id: first_listing.id, media_asset_ids: [ asset.id ] }
      }
    }.not_to change(Message, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "puts the conversation with the newest unread message before newer read conversations" do
    unread = Conversation.create!(organization:, kind: :internal, subject: "Unread room")
    read = Conversation.create!(organization:, kind: :internal, subject: "Read room")
    [ unread, read ].each do |conversation|
      conversation.conversation_memberships.create!(user: manager, role: :manager)
      conversation.conversation_memberships.create!(user: producer, role: :participant)
    end
    unread_time = 2.hours.ago
    unread.messages.create!(author: producer, body: "Needs attention", created_at: unread_time, updated_at: unread_time)
    unread.update_columns(last_message_at: unread_time, updated_at: unread_time)
    read_time = 30.minutes.ago
    read.messages.create!(author: producer, body: "Already handled", created_at: read_time, updated_at: read_time)
    read.update_columns(last_message_at: read_time, updated_at: read_time)
    read.conversation_memberships.find_by!(user: manager).update_columns(last_read_at: Time.current)

    get "/api/v1/conversations"

    expect(response).to have_http_status(:ok)
    conversations = response.parsed_body.fetch("conversations")
    expect(conversations.first).to include("id" => unread.id, "unread_count" => 1)
    expect(conversations.second).to include("id" => read.id, "unread_count" => 0)
  end

  it "marks a conversation read when it is opened" do
    conversation = Conversation.create!(organization:, kind: :internal, subject: "Read on open").tap do |record|
      record.conversation_memberships.create!(user: manager, role: :manager)
      record.conversation_memberships.create!(user: producer, role: :participant)
    end
    conversation.messages.create!(author: producer, body: "Open me")

    expect {
      get "/api/v1/conversations/#{conversation.id}"
    }.to change { conversation.conversation_memberships.find_by!(user: manager).reload.last_read_at }

    expect(response).to have_http_status(:ok)
    expect(conversation.conversation_memberships.find_by!(user: manager).last_read_at).to be_present
  end

  it "keeps a client from adding a message to a staff-only conversation" do
    conversation = Conversation.create!(organization:, kind: :internal, subject: "Staff only").tap do |record|
      record.conversation_memberships.create!(user: manager, role: :manager)
    end
    sign_out manager
    sign_in client_user

    post "/api/v1/conversations/#{conversation.id}/messages", params: { message: { body: "Not allowed" } }

    expect(response).to have_http_status(:not_found)
    expect(conversation.messages).to be_empty
  end

  it "does not accept a conversation member from another organization" do
    foreign_user = User.create!(organization: other_organization, name: "Foreign", email: "foreign-conversation@example.test",
                                password: "long-enough-password", role: :production_staff)

    post "/api/v1/conversations", params: {
      conversation: { kind: "internal", subject: "Cross tenant", member_ids: [ foreign_user.id ] }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Conversation.find_by(subject: "Cross tenant")).to be_nil
  end
end
