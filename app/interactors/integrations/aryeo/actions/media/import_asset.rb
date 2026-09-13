module Integrations::Aryeo::Actions::Media
  class ImportAsset < ApplicationInteractor
      def call
        importer = context.fetch(:importer)
        listing = context.fetch(:listing)
        payload = context.fetch(:payload)
        category = context.fetch(:category)
        external = importer.media_external_id(payload)
        return context.set(:asset, nil) if external.blank?

        source_url = importer.media_value(payload, *::Aryeo::Importer::MEDIA_SOURCE_KEYS.fetch(category, ::Aryeo::Importer::MEDIA_SOURCE_KEYS["files"])).to_s.presence
        asset = importer.media_record_for(external)&.record
        asset ||= importer.organization.media_assets.build(listing:, metadata: { "aryeo_id" => external })
        filename = importer.media_filename(payload, external, source_url)
        metadata = asset.metadata.merge("aryeo_id" => external)
        if source_url.present?
          metadata["aryeo_source_url"] = source_url
          metadata.delete("processing_error")
        else
          metadata["processing_error"] = "missing_media_url"
          importer.media_record_error("media_assets #{external}: Aryeo #{category} record has no downloadable URL")
        end
        content_type = importer.media_content_type_for(category, payload, source_url)
        asset.assign_attributes(
          listing:,
          filename:,
          content_type:,
          byte_size: importer.media_integer_value(payload, "byte_size", "filesize", "size"),
          width: importer.media_integer_value(payload, "width"),
          height: importer.media_integer_value(payload, "height"),
          duration_seconds: importer.media_integer_value(payload, "duration_seconds", "duration"),
          category: importer.media_category_for(category, content_type),
          position: importer.media_integer_value(payload, "index", "order_index", "position") || 0,
          status: source_url.present? ? :pending : :failed,
          storage_key: asset.storage_key.presence || DeliveryStorage.key_for(organization: importer.organization, listing:, filename:),
          source_url: nil,
          customer_visible: true,
          origin: :aryeo,
          metadata:
        )
        asset.save!
        importer.media_increment(source_url.present? ? "queued" : "failed")
        external_record = importer.media_archive(
          "media_assets", payload, record: asset, metadata: { "media_url" => source_url },
          sync_status: source_url.present? ? :pending_media_copy : :failed
        )
        ::AryeoMediaCopyJob.perform_later(external_record.id) if source_url.present? && !asset.ready?

        context.set(:asset, asset).set(:external_record, external_record)
      rescue ActiveRecord::RecordInvalid => error
        context.fail!(code: "record_validation_failure",
                      message: error.record.errors.full_messages.to_sentence,
                      original_error: error,
                      external_id: external)
      end
  end
end
