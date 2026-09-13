module MediaAssets
  class VerifyUpload < ApplicationInteractor
    def call
      asset = context.fetch(:asset)

      asset.with_lock do
        return context if asset.ready?

        asset.processing!
        raise DeliveryStorage::MissingFile, "Upload was not found" unless DeliveryStorage.exist?(asset.storage_key)

        asset.update!(status: :ready, processed_at: Time.current, metadata: asset.metadata.except("processing_error"))
      end

      context.set(:asset, asset)
    rescue DeliveryStorage::MissingFile => error
      asset.update(status: :failed, metadata: asset.metadata.merge("processing_error" => "upload_missing"))
      context.fail!(code: "upload_missing", message: error.message, original_error: error, asset_id: asset.id)
    end
  end
end
