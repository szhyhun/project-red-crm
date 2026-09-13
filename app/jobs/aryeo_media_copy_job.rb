class AryeoMediaCopyJob < ApplicationJob
  queue_as :media
  retry_on Aryeo::RemoteMediaCopy::RetryableError, wait: 30.seconds, attempts: 5

  def perform(external_record_id)
    external_record = ExternalRecord.find(external_record_id)
    result = Aryeo::CopyMedia.call(external_record:, executions:)
    raise result.failure.original_error || result.failure if result.failure?
  end
end
