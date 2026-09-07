module Conversations
  class RetentionJob < ApplicationJob
    queue_as :maintenance

    def perform
      result = Conversations::Retention.call
      Rails.logger.info(
        "Conversation retention completed: #{result.messages_deleted} messages, " \
        "#{result.attachments_deleted} attachments deleted, #{result.failures} failures"
      )
    end
  end
end
