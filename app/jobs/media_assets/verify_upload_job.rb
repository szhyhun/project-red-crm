module MediaAssets
  class VerifyUploadJob < ApplicationJob
    queue_as :media

    def perform(media_asset_id)
      asset = MediaAsset.find_by(id: media_asset_id)
      return unless asset

      asset.with_lock do
        return if asset.ready?

        asset.processing!
        raise DeliveryStorage::MissingFile, "Upload was not found" unless DeliveryStorage.exist?(asset.storage_key)

        asset.update!(status: :ready, processed_at: Time.current, metadata: asset.metadata.except("processing_error"))
      end
    rescue DeliveryStorage::MissingFile => error
      asset&.update(status: :failed, metadata: asset.metadata.merge("processing_error" => error.message))
    end
  end
end
