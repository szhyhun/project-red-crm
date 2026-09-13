module Integrations::Aryeo::Actions
  class CopyMedia < ApplicationInteractor
    FINAL_ATTEMPT = 5

    def call
      external_record = context.fetch(:external_record)
      asset = external_record.record
      return context.set(:skipped, true) unless asset.is_a?(MediaAsset)

      ::Aryeo::RemoteMediaCopy.call(
        asset:,
        source_url: external_record.metadata["media_url"],
        api_key: external_record.integration_connection.api_key
      )
      external_record.update!(sync_status: :copied)
      context.set(:external_record, external_record).set(:asset, asset)
    rescue ::Aryeo::RemoteMediaCopy::RetryableError => error
      Rails.logger.warn("Aryeo media copy failed: #{error.class}: #{error.message}")
      metadata = external_record.metadata.merge("media_copy_error" => "media_copy_failed")
      if context.fetch(:executions, 0).to_i >= FINAL_ATTEMPT
        external_record.update!(sync_status: :failed, metadata:)
        asset&.update!(status: :failed, metadata: asset.metadata.merge("processing_error" => "media_copy_failed"))
      else
        external_record.update!(metadata:)
      end
      context.fail!(code: "media_copy_failed", message: error.message, original_error: error,
                    external_record_id: external_record.id, asset_id: asset&.id)
    end
  end
end
