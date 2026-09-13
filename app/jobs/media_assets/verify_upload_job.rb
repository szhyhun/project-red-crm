module MediaAssets
  class VerifyUploadJob < ApplicationJob
    queue_as :media

    def perform(media_asset_id)
      asset = MediaAsset.find_by(id: media_asset_id)
      return unless asset

      result = VerifyUpload.call(asset:)
      return unless result.failure?

      Rails.logger.warn("Media asset verification failed: #{result.failure.class}: #{result.failure.message}")
    end
  end
end
