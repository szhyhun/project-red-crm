module Conversations
  class RetentionJob < ApplicationJob
    queue_as :maintenance

    # Resque Scheduler invokes jobs through Resque's class-level perform API.
    # Keep the actual work in Active Job so this scheduled entry and any
    # application-triggered execution share the same implementation.
    def self.perform
      perform_now
    end

    def perform
      result = Conversations::PurgeExpired.call
      Rails.logger.info(
        "Conversation retention completed: #{result.messages_deleted} messages, " \
        "#{result.attachments_deleted} attachments deleted, #{result.failures} failures"
      )
    end
  end
end
