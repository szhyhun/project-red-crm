module Conversations
  # Persists a message and its media references as one unit, then announces
  # the committed message asynchronously. Redis or Action Cable availability
  # must never decide whether the user's message exists.
  class PublishMessage < ApplicationInteractor
    def call
      conversation = context.fetch(:conversation)
      author = context.fetch(:author)
      assets = Array(context[:media_assets])

      message = nil
      Conversation.transaction do
        message = conversation.messages.create!(
          author:,
          body: context.fetch(:body),
          body_html: context[:body_html],
          visibility: message_visibility(author),
          message_kind: context.fetch(:message_kind, :message),
          listing: context[:listing],
          order_deliverable: context[:order_deliverable],
          media_review: context[:media_review]
        )
        assets.each_with_index do |asset, position|
          message.message_media_references.create!(media_asset: asset, position:)
        end
        conversation.update!(last_message_at: message.created_at)
      end

      enqueue_notification(message)
      context.set(:message, message)
    rescue ActiveRecord::RecordInvalid => error
      context.fail!(
        code: "message_invalid",
        message: error.record.errors.full_messages.to_sentence,
        original_error: error,
        conversation_id: context[:conversation]&.id
      )
    end

    private

    def message_visibility(author)
      return :participants unless author.internal?

      context[:visibility].presence || :participants
    end

    def enqueue_notification(message)
      Conversations::NotifyJob.perform_later(message.id)
    rescue StandardError => error
      Rails.logger.error(
        "Could not queue conversation notification for message #{message.id}: #{error.class}: #{error.message}"
      )
    end
  end
end
