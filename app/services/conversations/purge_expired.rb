require "set"

module Conversations
  class PurgeExpired
    BATCH_SIZE = 100

    Result = Data.define(:messages_deleted, :attachments_deleted, :failures)

    class << self
      def call(now: Time.current, batch_size: BATCH_SIZE)
        new(now:, batch_size:).call
      end
    end

    def initialize(now:, batch_size:)
      @now = now
      @batch_size = batch_size
      @messages_deleted = 0
      @attachments_deleted = 0
      @failures = 0
      @conversation_ids = Set.new
    end

    def call
      expiring_conversations.find_each do |conversation|
        cutoff = conversation.retention_cutoff(@now)
        conversation.messages.where("messages.created_at < ?", cutoff).find_each(batch_size: @batch_size) do |message|
          purge_message(message)
        end
      end

      refresh_conversation_timestamps
      result
    end

    private

    def expiring_conversations
      Conversation.where.not(retention_period: Conversation.retention_periods.fetch("forever"))
    end

    def purge_message(message)
      message.with_lock do
        # A message may have been edited or moved past the cutoff while this
        # sweep was waiting for its row lock.
        conversation = message.conversation
        next if conversation.forever? || message.created_at >= conversation.retention_cutoff(@now)

        message.conversation_attachments.find_each do |attachment|
          # Remove the private object first. If storage is unavailable, keep
          # the database row so the next sweep can retry without data loss.
          ConversationStorage.delete(attachment.storage_key)
          attachment.destroy!
          @attachments_deleted += 1
        end

        conversation_id = message.conversation_id
        message.destroy!
        @conversation_ids << conversation_id
        @messages_deleted += 1
      end
    rescue ActiveRecord::RecordNotFound
      # Another cleanup run may have removed the row after find_each loaded it.
    rescue StandardError => error
      @failures += 1
      Rails.logger.warn(
        "Conversation retention skipped message #{message.id}: #{error.class}: #{error.message}"
      )
    end

    def refresh_conversation_timestamps
      Conversation.where(id: @conversation_ids.to_a).find_each do |conversation|
        conversation.update_columns(last_message_at: conversation.messages.maximum(:created_at))
      end
    end

    def result
      Result.new(
        messages_deleted: @messages_deleted,
        attachments_deleted: @attachments_deleted,
        failures: @failures
      )
    end
  end
end
