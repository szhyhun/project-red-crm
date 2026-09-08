require "rails_helper"

RSpec.describe "Conversation attachment access", type: :request do
  let!(:organization) { Organization.create!(name: "Attachment access agency", slug: "attachment-access-agency") }
  let!(:admin) do
    User.create!(organization:, name: "Attachment admin", email: "attachment-admin@example.test",
                 password: "long-enough-password", role: :organization_admin)
  end
  let!(:manager) do
    User.create!(organization:, name: "Attachment manager", email: "attachment-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:participant) do
    User.create!(organization:, name: "Attachment participant", email: "attachment-participant@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:conversation) do
    Conversation.create!(organization:, kind: :internal, subject: "Attachment permissions").tap do |record|
      record.conversation_memberships.create!(user: manager, role: :manager)
      record.conversation_memberships.create!(user: participant, role: :participant)
    end
  end
  let!(:message) { conversation.messages.create!(author: manager, body: "Files") }

  def attachment(uploaded_by:, filename:)
    conversation.conversation_attachments.create!(organization:, message:, uploaded_by:, status: :ready,
                                                  storage_key: "organizations/#{organization.id}/conversations/#{conversation.id}/#{filename}",
                                                  filename:, content_type: "text/plain", byte_size: 5)
  end

  it "does not let a participant delete another member's attachment" do
    record = attachment(uploaded_by: manager, filename: "manager.txt")
    allow(ConversationStorage).to receive(:delete)
    sign_in participant

    delete "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{record.id}"

    expect(response).to have_http_status(:forbidden)
    expect(record.reload).to be_ready
    expect(ConversationStorage).not_to have_received(:delete)
  end

  it "lets the uploader delete their own attachment" do
    record = attachment(uploaded_by: participant, filename: "participant.txt")
    allow(ConversationStorage).to receive(:delete)
    sign_in participant

    delete "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{record.id}"

    expect(response).to have_http_status(:no_content)
    expect(ConversationAttachment.exists?(record.id)).to be(false)
    expect(ConversationStorage).to have_received(:delete).with(record.storage_key)
  end

  it "lets an organization administrator delete a member's attachment" do
    record = attachment(uploaded_by: participant, filename: "admin-delete.txt")
    allow(ConversationStorage).to receive(:delete)
    sign_in admin

    delete "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{record.id}"

    expect(response).to have_http_status(:no_content)
    expect(ConversationAttachment.exists?(record.id)).to be(false)
  end

  it "does not cross message boundaries when resolving an attachment" do
    other_message = conversation.messages.create!(author: manager, body: "Other message")
    record = attachment(uploaded_by: manager, filename: "boundary.txt")
    sign_in participant

    get "/api/v1/conversations/#{conversation.id}/messages/#{other_message.id}/attachments/#{record.id}/preview"

    expect(response).to have_http_status(:not_found)
  end
end
