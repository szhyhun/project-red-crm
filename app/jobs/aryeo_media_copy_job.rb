class AryeoMediaCopyJob < ApplicationJob
  queue_as :media
  retry_on Aryeo::RemoteMediaCopy::RetryableError, wait: 30.seconds, attempts: 5

  def perform(external_record_id)
    external_record = ExternalRecord.find(external_record_id)
    asset = external_record.record
    return unless asset.is_a?(MediaAsset)

    Aryeo::RemoteMediaCopy.call(asset:, source_url: external_record.metadata["media_url"])
    external_record.update!(sync_status: :copied)
  rescue Aryeo::RemoteMediaCopy::RetryableError => error
    metadata = external_record.metadata.merge("media_copy_error" => error.message)
    if executions.to_i >= 5
      external_record.update!(sync_status: :failed, metadata:)
      asset&.update!(status: :failed, metadata: asset.metadata.merge("processing_error" => error.message))
    else
      external_record.update!(metadata:)
    end
    raise
  end
end
