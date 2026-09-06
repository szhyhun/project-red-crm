class ConversationAttachment < ApplicationRecord
  belongs_to :organization
  belongs_to :conversation
  belongs_to :message
  belongs_to :uploaded_by, class_name: "User", optional: true

  enum :status, { pending: "pending", ready: "ready", failed: "failed" }, validate: true

  ALLOWED_CONTENT_TYPES = %r{
    \A(?:
      image/(?!svg\+xml(?:;|$))[^\s;]+|
      video/[^\s;]+|
      application/(?:pdf|zip|gzip|msword|vnd\.openxmlformats-officedocument\.[^\s;]+|vnd\.ms-excel[^\s;]*|vnd\.ms-powerpoint[^\s;]*)|
      text/(?:plain|csv|markdown)
    )\z
  }ix

  validates :filename, :content_type, :storage_key, presence: true
  validates :byte_size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: ->(_record) { ConversationAttachment.max_bytes } }
  validate :content_type_is_supported
  validate :parent_records_match

  def self.max_bytes
    ENV.fetch("CHAT_MEDIA_MAX_BYTES", 500.megabytes).to_i
  end

  def self.serialize(attachment)
    attachment.slice(:id, :conversation_id, :message_id, :status, :filename, :content_type, :byte_size, :metadata,
                      :processed_at, :created_at).merge(
      # Keep the storage key private. The API endpoints enforce conversation
      # membership before reading from the chat bucket.
      preview_path: "/api/v1/conversations/#{attachment.conversation_id}/messages/#{attachment.message_id}/attachments/#{attachment.id}/preview",
      download_path: "/api/v1/conversations/#{attachment.conversation_id}/messages/#{attachment.message_id}/attachments/#{attachment.id}/download",
      uploaded_by: attachment.uploaded_by&.slice(:id, :name)
    )
  end

  private

  def content_type_is_supported
    return if content_type.to_s.match?(ALLOWED_CONTENT_TYPES)

    errors.add(:content_type, "is not supported for conversation attachments")
  end

  def parent_records_match
    if message.present? && message.conversation_id != conversation_id
      errors.add(:message, "must belong to the conversation")
    end

    if conversation.present? && conversation.organization_id != organization_id
      errors.add(:conversation, "must belong to the organization")
    end

    if message.present? && message.conversation.organization_id != organization_id
      errors.add(:message, "must belong to the organization")
    end
  end
end
