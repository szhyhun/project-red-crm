require "rails_helper"

RSpec.describe Conversations::PurgeExpired do
  let!(:organization) { Organization.create!(name: "Retention service agency", slug: "retention-service-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Retention manager", email: "retention-service-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:conversation) do
    Conversation.create!(organization:, kind: :internal, subject: "Retention service room").tap do |record|
      record.conversation_memberships.create!(user: manager, role: :manager)
    end
  end
  let(:now) { Time.zone.parse("2026-09-08 12:00:00") }

  def message_at(created_at, body: "Message")
    conversation.messages.create!(author: manager, body:, created_at:, updated_at: created_at)
  end

  it "deletes expired messages and their private objects, then refreshes last activity" do
    expired = message_at(now - 61.days, body: "Expired")
    current = message_at(now - 1.day, body: "Keep")
    attachment = conversation.conversation_attachments.create!(organization:, message: expired, uploaded_by: manager,
                                                                status: :ready, storage_key: "retention/expired.txt",
                                                                filename: "expired.txt", content_type: "text/plain",
                                                                byte_size: 5)
    conversation.update_columns(last_message_at: expired.created_at, updated_at: expired.created_at)
    allow(ConversationStorage).to receive(:delete)

    result = described_class.call(now:, batch_size: 1)

    expect(result.fetch(:messages_deleted)).to eq(1)
    expect(result.fetch(:attachments_deleted)).to eq(1)
    expect(result.fetch(:failures)).to eq(0)
    expect(Message).not_to exist(expired.id)
    expect(ConversationAttachment).not_to exist(attachment.id)
    expect(conversation.reload.last_message_at).to eq(current.created_at)
    expect(ConversationStorage).to have_received(:delete).with(attachment.storage_key)
  end

  it "does not delete a message exactly on the retention cutoff" do
    boundary = message_at(now - 60.days, body: "Boundary")

    result = described_class.call(now:)

    expect(result.fetch(:messages_deleted)).to eq(0)
    expect(result.fetch(:attachments_deleted)).to eq(0)
    expect(result.fetch(:failures)).to eq(0)
    expect(Message).to exist(boundary.id)
  end

  it "leaves conversations configured to keep history forever untouched" do
    conversation.update!(retention_period: :forever)
    old_message = message_at(now - 10.years, body: "Keep forever")

    result = described_class.call(now:)

    expect(result.fetch(:messages_deleted)).to eq(0)
    expect(result.fetch(:attachments_deleted)).to eq(0)
    expect(result.fetch(:failures)).to eq(0)
    expect(Message).to exist(old_message.id)
  end

  it "keeps database rows when private storage deletion fails so the next sweep can retry" do
    expired = message_at(now - 61.days, body: "Retry me")
    attachment = conversation.conversation_attachments.create!(organization:, message: expired, uploaded_by: manager,
                                                                status: :ready, storage_key: "retention/retry.txt",
                                                                filename: "retry.txt", content_type: "text/plain",
                                                                byte_size: 5)
    allow(ConversationStorage).to receive(:delete).and_raise(ConversationStorage::WriteError, "bucket unavailable")

    result = described_class.call(now:)

    expect(result.fetch(:messages_deleted)).to eq(0)
    expect(result.fetch(:attachments_deleted)).to eq(0)
    expect(result.fetch(:failures)).to eq(1)
    expect(Message).to exist(expired.id)
    expect(ConversationAttachment).to exist(attachment.id)
  end
end
