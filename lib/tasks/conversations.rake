namespace :conversations do
  desc "Delete chat messages and private attachments older than the configured retention window"
  task purge_expired: :environment do
    result = Conversations::Retention.call
    puts(
      "Deleted #{result.messages_deleted} messages and #{result.attachments_deleted} attachments " \
      "older than #{result.retention_days} days (#{result.failures} failures)."
    )
  end
end
