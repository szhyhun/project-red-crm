require "fileutils"
require "securerandom"
require "uri"
require "aws-sdk-s3"

class DeliveryStorage
  class MissingFile < StandardError; end
  class WriteError < StandardError; end

  ROOT = Rails.root.join("storage", "deliveries").freeze

  class << self
    def key_for(organization:, listing:, filename:)
      safe_filename = filename.to_s.parameterize.presence || "asset"
      "organizations/#{organization.id}/listings/#{listing.id}/#{SecureRandom.uuid}-#{safe_filename}"
    end

    def write(upload:, key:, content_type: nil)
      if s3?
        options = { bucket: media_bucket, key: key, body: upload }
        options[:content_type] = content_type if content_type.present?
        return s3_client.put_object(**options)
      end

      destination = path_for(key)
      FileUtils.mkdir_p(destination.dirname)
      File.open(destination, "wb") { |file| IO.copy_stream(upload, file) }
    rescue SystemCallError, IOError => error
      FileUtils.rm_f(destination) if destination
      raise WriteError, error.message
    end

    def delete(key)
      return s3_client.delete_object(bucket: media_bucket, key: key) if s3?

      FileUtils.rm_f(path_for(key))
    end

    def exist?(key)
      return s3_client.head_object(bucket: media_bucket, key: key) && true if s3?

      path_for(key).file?
    rescue Aws::S3::Errors::NotFound
      false
    end

    def path_for(key)
      candidate = ROOT.join(key.to_s).cleanpath
      raise MissingFile, "Invalid delivery storage key" unless candidate.to_s.start_with?("#{ROOT}/")

      candidate
    end

    def public_url(key)
      return if key.blank? || media_cdn_url.blank?

      "#{media_cdn_url.chomp("/")}/#{escape_key(key)}"
    end

    def temporary_url(key, content_type: nil)
      return unless s3? && key.present?

      options = { bucket: media_bucket, key: key, expires_in: 15.minutes.to_i }
      options[:response_content_type] = content_type if content_type.present?
      Aws::S3::Presigner.new(client: s3_client).presigned_url(:get_object, **options)
    end

    def s3?
      media_bucket.present?
    end

    private

    def media_bucket
      ENV["PROJECT_RED_MEDIA_BUCKET"].presence
    end

    def media_cdn_url
      ENV["PROJECT_RED_MEDIA_CDN_URL"].presence || ENV["MEDIA_CDN_URL"].presence
    end

    def s3_client
      @s3_client ||= Aws::S3::Client.new(region: ENV.fetch("AWS_REGION", "us-west-2"))
    end

    def escape_key(key)
      key.to_s.split("/").map { |segment| URI::DEFAULT_PARSER.escape(segment) }.join("/")
    end
  end
end
