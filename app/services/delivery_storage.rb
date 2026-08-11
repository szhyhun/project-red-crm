require "fileutils"
require "securerandom"

class DeliveryStorage
  class MissingFile < StandardError; end
  class WriteError < StandardError; end

  ROOT = Rails.root.join("storage", "deliveries").freeze

  class << self
    def key_for(organization:, listing:, filename:)
      safe_filename = filename.to_s.parameterize.presence || "asset"
      "organizations/#{organization.id}/listings/#{listing.id}/#{SecureRandom.uuid}-#{safe_filename}"
    end

    def write(upload:, key:)
      destination = path_for(key)
      FileUtils.mkdir_p(destination.dirname)
      File.open(destination, "wb") { |file| IO.copy_stream(upload, file) }
    rescue SystemCallError, IOError => error
      FileUtils.rm_f(destination) if destination
      raise WriteError, error.message
    end

    def delete(key)
      FileUtils.rm_f(path_for(key))
    end

    def exist?(key)
      path_for(key).file?
    end

    def path_for(key)
      candidate = ROOT.join(key.to_s).cleanpath
      raise MissingFile, "Invalid delivery storage key" unless candidate.to_s.start_with?("#{ROOT}/")

      candidate
    end
  end
end
