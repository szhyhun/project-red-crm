require "rails_helper"

RSpec.describe "Conversation deletion", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-chat-delete") }
  let!(:admin) do
    User.create!(organization:, name: "Alex Admin", email: "chat-admin@example.test",
                 password: "long-enough-password", role: :organization_admin)
  end
  let!(:manager) do
    User.create!(organization:, name: "Morgan Manager", email: "chat-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:conversation) do
    Conversation.create!(organization:, kind: :internal, subject: "Production standup").tap do |record|
      record.conversation_memberships.create!(user: manager, role: :manager)
      record.messages.create!(author: manager, body: "Morning all")
    end
  end

  it "lets an organization admin delete a conversation and its history" do
    sign_in admin

    delete "/api/v1/conversations/#{conversation.id}"

    expect(response).to have_http_status(:no_content)
    expect(Conversation.exists?(conversation.id)).to be(false)
    expect(Message.where(conversation_id: conversation.id)).to be_empty
    expect(ConversationMembership.where(conversation_id: conversation.id)).to be_empty
  end

  it "refuses a manager who only manages the conversation's members" do
    sign_in manager

    delete "/api/v1/conversations/#{conversation.id}"

    expect(response).to have_http_status(:forbidden)
    expect(Conversation.exists?(conversation.id)).to be(true)
  end

  it "does not let an admin reach a conversation in another organization" do
    other = Organization.create!(name: "Rival", slug: "rival-chat-delete")
    other_conversation = Conversation.create!(organization: other, kind: :internal, subject: "Theirs")
    sign_in admin

    delete "/api/v1/conversations/#{other_conversation.id}"

    expect(response).to have_http_status(:not_found)
    expect(Conversation.exists?(other_conversation.id)).to be(true)
  end
end
