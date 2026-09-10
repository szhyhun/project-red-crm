class AryeoMediaCopyJob < ApplicationJob
  queue_as :media
  retry_on Aryeo::RemoteMediaCopy::RetryableError, wait: 30.seconds, attempts: 5

  def perform(external_record_id)
    external_record = ExternalRecord.find(external_record_id)
    asset = external_record.record
    return unless asset.is_a?(MediaAsset)

    Aryeo::RemoteMediaCopy.call(asset:, source_url: external_record.metadata["media_url"],
                                api_key: external_record.integration_connection.api_key)
    external_record.update!(sync_status: :copied)
  rescue Aryeo::RemoteMediaCopy::RetryableError => error
    Rails.logger.warn("Aryeo media copy failed: #{error.class}: #{error.message}")
    metadata = external_record.metadata.merge("media_copy_error" => "media_copy_failed")
    if executions.to_i >= 5
      external_record.update!(sync_status: :failed, metadata:)
      asset&.update!(status: :failed, metadata: asset.metadata.merge("processing_error" => "media_copy_failed"))
    else
      external_record.update!(metadata:)
    end
    raise
  end
end
