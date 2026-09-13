require "rails_helper"

RSpec.describe Conversations::PurgeExpired do
  let!(:organization) { Organization.create!(name: "Retention Agency", slug: "retention-agency") }
  let!(:author) do
    User.create!(organization:, name: "Retention User", email: "retention@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:conversation) do
    Conversation.create!(organization:, kind: :internal, subject: "Retention room", retention_period: :two_months)
  end
  let(:now) { Time.zone.parse("2026-09-07 12:00:00") }

  def create_message(room, body, created_at:)
    room.messages.create!(
      author:, body:, created_at:, updated_at: created_at
    )
  end

  def create_attachment(room, message, storage_key, created_at:)
    message.conversation_attachments.create!(
      organization: room.organization, conversation: room, uploaded_by: author, status: :ready, storage_key:,
      filename: "photo.jpg",
      content_type: "image/jpeg", byte_size: 1, created_at:, updated_at: created_at
    )
  end

  it "deletes expired messages and their chat objects while keeping recent history" do
    old_time = 61.days.ago(now)
    recent_time = 59.days.ago(now)
    old_message = create_message(conversation, "old", created_at: old_time)
    old_attachment = create_attachment(conversation, old_message, "old-key", created_at: old_time)
    recent_message = create_message(conversation, "recent", created_at: recent_time)
    recent_attachment = create_attachment(conversation, recent_message, "recent-key", created_at: recent_time)
    allow(ConversationStorage).to receive(:delete)

    result = described_class.call(now:)

    expect(result.fetch(:messages_deleted)).to eq(1)
    expect(result.fetch(:attachments_deleted)).to eq(1)
    expect(result.fetch(:failures)).to eq(0)
    expect(ConversationStorage).to have_received(:delete).with(old_attachment.storage_key)
    expect(Message.exists?(old_message.id)).to be(false)
    expect(ConversationAttachment.exists?(old_attachment.id)).to be(false)
    expect(Message.exists?(recent_message.id)).to be(true)
    expect(ConversationAttachment.exists?(recent_attachment.id)).to be(true)
    expect(conversation.reload.last_message_at).to eq(recent_time)
  end

  it "keeps a message when deleting its chat object fails so the sweep can retry" do
    old_time = 61.days.ago(now)
    failed_message = create_message(conversation, "keep me", created_at: old_time)
    failed_attachment = create_attachment(conversation, failed_message, "failed-key", created_at: old_time)
    deleted_message = create_message(conversation, "delete me", created_at: old_time - 1.minute)
    deleted_attachment = create_attachment(conversation, deleted_message, "deleted-key", created_at: old_time - 1.minute)
    allow(ConversationStorage).to receive(:delete).with(failed_attachment.storage_key).and_raise(StandardError, "S3 unavailable")
    allow(ConversationStorage).to receive(:delete).with(deleted_attachment.storage_key)

    result = described_class.call(now:)

    expect(result.fetch(:messages_deleted)).to eq(1)
    expect(result.fetch(:attachments_deleted)).to eq(1)
    expect(result.fetch(:failures)).to eq(1)
    expect(Message.exists?(failed_message.id)).to be(true)
    expect(ConversationAttachment.exists?(failed_attachment.id)).to be(true)
    expect(Message.exists?(deleted_message.id)).to be(false)
  end

  it "does not delete history from a conversation configured to retain it forever" do
    forever_conversation = Conversation.create!(organization:, kind: :internal, subject: "Permanent room", retention_period: :forever)
    message = create_message(forever_conversation, "keep me forever", created_at: 2.years.ago(now))

    result = described_class.call(now:)

    expect(result.fetch(:messages_deleted)).to eq(0)
    expect(Message.exists?(message.id)).to be(true)
  end
end
