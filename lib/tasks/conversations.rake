namespace :conversations do
  desc "Delete chat messages and private attachments past each conversation's retention period"
  task purge_expired: :environment do
    result = Conversations::PurgeExpired.call
    puts(
      "Deleted #{result.messages_deleted} messages and #{result.attachments_deleted} attachments " \
      "using each conversation's retention period (#{result.failures} failures)."
    )
  end
end
