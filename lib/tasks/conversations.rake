namespace :conversations do
  desc "Delete chat messages and private attachments past each conversation's retention period"
  task purge_expired: :environment do
    result = Conversations::PurgeExpired.call
    raise result.failure.original_error || result.failure if result.failure?
    puts(
      "Deleted #{result.fetch(:messages_deleted)} messages and #{result.fetch(:attachments_deleted)} attachments " \
      "using each conversation's retention period (#{result.fetch(:failures)} failures)."
    )
  end
end
