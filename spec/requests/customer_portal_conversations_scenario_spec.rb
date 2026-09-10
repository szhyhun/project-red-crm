require "rails_helper"

RSpec.describe "Customer portal conversations API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Portal conversation agency", slug: "portal-conversation-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Portal conversation manager", email: "portal-conversation-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_user) do
    User.create!(organization:, name: "Portal conversation customer", email: "portal-conversation-client@example.test",
                 password: "long-enough-password", role: :client_admin)
  end
  let!(:first_account) { ClientAccount.create!(organization:, name: "First portal account", kind: :agent) }
  let!(:second_account) { ClientAccount.create!(organization:, name: "Second portal account", kind: :agent) }
  let!(:hidden_account) { ClientAccount.create!(organization:, name: "Hidden portal account", kind: :agent) }
  let!(:first_listing) { Listing.create!(organization:, client_account: first_account, address_line_1: "41 Portal Chat Street") }
  let!(:second_listing) { Listing.create!(organization:, client_account: second_account, address_line_1: "42 Portal Chat Street") }

  before do
    ClientMembership.create!(client_account: first_account, user: client_user, role: :admin)
    ClientMembership.create!(client_account: second_account, user: client_user, role: :member)
    allow(Conversations::NotifyJob).to receive(:perform_later)
  end

  it "keeps customer conversations out of the list until the customer is a member" do
    hidden = customer_conversation(hidden_account, "Hidden customer room")
    sign_in client_user

    get "/api/v1/conversations"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("conversations")).to be_empty
    expect(hidden.conversation_memberships.pluck(:user_id)).to eq([ manager.id ])
  end

  it "sorts a customer's conversations by their latest message while preserving unread counts" do
    unread = customer_conversation(first_account, "Unread customer room")
    read = customer_conversation(second_account, "Read customer room")
    unread_time = 2.hours.ago
    read_time = 20.minutes.ago
    unread.messages.create!(author: manager, body: "Please review the photos.", created_at: unread_time, updated_at: unread_time)
    read.messages.create!(author: manager, body: "Already read update.", created_at: read_time, updated_at: read_time)
    unread.update_columns(last_message_at: unread_time, updated_at: unread_time)
    read.update_columns(last_message_at: read_time, updated_at: read_time)
    read.conversation_memberships.find_by!(user: client_user).update_columns(last_read_at: Time.current)
    sign_in client_user

    get "/api/v1/conversations"

    expect(response).to have_http_status(:ok)
    conversations = response.parsed_body.fetch("conversations")
    expect(conversations.first).to include("id" => read.id, "unread_count" => 0)
    expect(conversations.second).to include("id" => unread.id, "unread_count" => 1)
  end

  it "lets a customer send a message and exposes it to staff with its account context" do
    conversation = customer_conversation(first_account, "Customer production room")
    sign_in client_user

    post "/api/v1/conversations/#{conversation.id}/messages", params: {
      message: { body: "Please confirm when the revised photos are ready.", listing_id: first_listing.id }
    }

    expect(response).to have_http_status(:created)
    message = conversation.messages.order(:id).last
    expect(message).to have_attributes(author: client_user, listing: first_listing, body: "Please confirm when the revised photos are ready.")
    expect(response.parsed_body.dig("message", "listing_id")).to eq(first_listing.id)
    expect(Conversations::NotifyJob).to have_received(:perform_later).with(message.id)

    sign_out client_user
    sign_in manager
    get "/api/v1/conversations/#{conversation.id}"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("conversation", "messages")).to include(
      include("id" => message.id, "body" => message.body, "listing_id" => first_listing.id)
    )
  end

  it "does not let a customer post account context from another account" do
    conversation = customer_conversation(first_account, "Context boundary room")
    sign_in client_user

    expect {
      post "/api/v1/conversations/#{conversation.id}/messages", params: {
        message: { body: "Wrong property", listing_id: second_listing.id }
      }
    }.not_to change(Message, :count)

    expect(response).to have_http_status(:not_found)
  end

  private

  def customer_conversation(account, subject)
    Conversation.create!(organization:, client_account: account, kind: :client, subject:).tap do |conversation|
      conversation.conversation_memberships.create!(user: manager, role: :manager)
      conversation.conversation_memberships.create!(user: client_user, role: :participant) unless account == hidden_account
    end
  end
end
