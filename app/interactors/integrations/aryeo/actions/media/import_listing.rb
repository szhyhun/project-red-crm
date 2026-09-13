module Integrations::Aryeo::Actions::Media
  class ImportListing < ApplicationInteractor
      def call
        importer = context.fetch(:importer)
        listing = context.fetch(:listing)
        payload = context.fetch(:payload)

        ::Aryeo::Importer::LISTING_MEDIA.each do |key, category|
          importer.media_records(payload, key).each do |media_payload|
            result = ImportAsset.call(importer:, listing:, payload: media_payload, category:)
            next if result.success?

            importer.media_increment("failed")
            importer.media_record_error(
              "media_assets #{importer.media_external_id(media_payload) || "unknown"}: " \
              "#{result.failure.message}"
            )
          end
        end

        context.set(:listing, listing)
      end
  end
end
