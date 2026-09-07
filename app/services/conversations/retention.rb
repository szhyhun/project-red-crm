require "set"

module Conversations
  class Retention
    DEFAULT_RETENTION_DAYS = 30
    RETENTION_DAYS_ENV = "PROJECT_RED_CHAT_RETENTION_DAYS"
    BATCH_SIZE = 100

    Result = Data.define(:retention_days, :cutoff, :messages_deleted, :attachments_deleted, :failures)

    class << self
      def call(retention_days: nil, now: Time.current, batch_size: BATCH_SIZE)
        new(retention_days:, now:, batch_size:).call
      end

      def retention_days
        normalize_days(ENV[RETENTION_DAYS_ENV])
      end

      private

      def normalize_days(value)
        days = Integer(value.to_s, 10)
        days.positive? ? days : DEFAULT_RETENTION_DAYS
      rescue ArgumentError, TypeError
        DEFAULT_RETENTION_DAYS
      end
    end

    def initialize(retention_days:, now:, batch_size:)
      @retention_days = self.class.send(:normalize_days, retention_days || self.class.retention_days)
      @now = now
      @batch_size = batch_size
      @cutoff = @now - @retention_days.days
      @messages_deleted = 0
      @attachments_deleted = 0
      @failures = 0
      @conversation_ids = Set.new
    end

    def call
      Message.where("messages.created_at < ?", @cutoff).find_each(batch_size: @batch_size) do |message|
        purge_message(message)
      end

      refresh_conversation_timestamps
      result
    end

    private

    def purge_message(message)
      message.with_lock do
        # A message may have been edited or moved past the cutoff while this
        # sweep was waiting for its row lock.
        next unless message.created_at < @cutoff

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
        retention_days: @retention_days,
        cutoff: @cutoff,
        messages_deleted: @messages_deleted,
        attachments_deleted: @attachments_deleted,
        failures: @failures
      )
    end
  end
end
