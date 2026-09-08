require "rails_helper"

RSpec.describe ConversationAttachment, type: :model do
  let!(:organization) { Organization.create!(name: "Attachment contract agency", slug: "attachment-contract-agency") }
  let!(:other_organization) do
    Organization.create!(name: "Other attachment contract agency", slug: "other-attachment-contract-agency")
  end
  let!(:author) do
    User.create!(organization:, name: "Attachment author", email: "attachment-author@example.test",
                password: "long-enough-password", role: :manager)
  end
  let!(:other_author) do
    User.create!(organization: other_organization, name: "Other author", email: "other-attachment-author@example.test",
                password: "long-enough-password", role: :manager)
  end
  let!(:conversation) { Conversation.create!(organization:, kind: :internal, subject: "Attachment room") }
  let!(:message) { conversation.messages.create!(author:, body: "Review this file") }

  def build_attachment(attributes = {})
    described_class.new({
      organization:, conversation:, message:, uploaded_by: author, status: :ready,
      storage_key: "organizations/#{organization.id}/conversations/#{conversation.id}/message/file.jpg",
      filename: "file.jpg", content_type: "image/jpeg", byte_size: 5
    }.merge(attributes))
  end

  it "accepts supported private files with a positive size" do
    expect(build_attachment).to be_valid
  end

  it "rejects an attachment whose message belongs to another conversation" do
    other_conversation = Conversation.create!(organization:, kind: :internal, subject: "Other room")
    other_message = other_conversation.messages.create!(author:, body: "Other message")

    attachment = build_attachment(message: other_message)

    expect(attachment).not_to be_valid
    expect(attachment.errors.full_messages).to include("Message must belong to the conversation")
  end

  it "rejects an attachment whose parent conversation belongs to another organization" do
    other_conversation = Conversation.create!(organization: other_organization, kind: :internal,
                                               subject: "Foreign room")
    other_message = other_conversation.messages.create!(author: other_author, body: "Foreign message")
    attachment = build_attachment(conversation: other_conversation, message: other_message)

    expect(attachment).not_to be_valid
    expect(attachment.errors.full_messages).to include(
      "Conversation must belong to the organization",
      "Message must belong to the organization"
    )
  end

  it "rejects active browser content and zero-byte files" do
    unsafe = build_attachment(content_type: "text/html", filename: "unsafe.html")
    empty = build_attachment(byte_size: 0)

    expect(unsafe).not_to be_valid
    expect(unsafe.errors.full_messages).to include("Content type is not supported for conversation attachments")
    expect(empty).not_to be_valid
    expect(empty.errors.full_messages).to include("Byte size must be greater than 0")
  end

  it "requires a storage key because chat files are private objects" do
    attachment = build_attachment(storage_key: nil)

    expect(attachment).not_to be_valid
    expect(attachment.errors.full_messages).to include("Storage key can't be blank")
  end

  it "serializes authorized API routes without leaking the private storage key" do
    attachment = conversation.conversation_attachments.create!(
      organization:, message:, uploaded_by: author, status: :ready,
      storage_key: "organizations/#{organization.id}/conversations/#{conversation.id}/message/private.jpg",
      filename: "private.jpg", content_type: "image/jpeg", byte_size: 5
    )

    serialized = described_class.serialize(attachment)

    expect(serialized.keys.map(&:to_s)).not_to include("storage_key")
    expect(serialized.fetch(:preview_path)).to eq(
      "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{attachment.id}/preview"
    )
    expect(serialized.fetch(:download_path)).to eq(
      "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{attachment.id}/download"
    )
  end
end
