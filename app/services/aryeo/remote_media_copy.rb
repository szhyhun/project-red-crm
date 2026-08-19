require "open-uri"
require "tempfile"

module Aryeo
  class RemoteMediaCopy
    class RetryableError < StandardError; end

    def self.call(asset:, source_url:)
      raise RetryableError, "Missing Aryeo media URL" if source_url.blank?

      URI.open(source_url, open_timeout: 15, read_timeout: 120) do |remote|
        DeliveryStorage.write(upload: remote, key: asset.storage_key)
      end
      asset.update!(status: :ready, processed_at: Time.current, source_url: nil,
                    metadata: asset.metadata.merge("aryeo_source_url" => source_url).except("processing_error"))
    rescue OpenURI::HTTPError, SocketError, Timeout::Error, IOError, DeliveryStorage::WriteError => error
      raise RetryableError, error.message
    end
  end
end
