require "fileutils"
require "securerandom"
require "uri"
require "aws-sdk-s3"

# Board files use a separate bucket and local root from listing delivery media.
# That makes retention, access policy, and future CDN rules independently
# adjustable without changing the storage contract for property assets.
class BoardStorage
  class MissingFile < StandardError; end
  class WriteError < StandardError; end

  ROOT = Rails.root.join("storage", "board_media").freeze

  class << self
    def key_for(organization:, board:, task:, filename:)
      safe_filename = filename.to_s.parameterize.presence || "attachment"
      "organizations/#{organization.id}/boards/#{board.id}/tasks/#{task.id}/#{SecureRandom.uuid}-#{safe_filename}"
    end

    def write(upload:, key:, content_type: nil)
      if s3?
        options = { bucket: board_media_bucket, key:, body: upload }
        options[:content_type] = content_type if content_type.present?
        return s3_client.put_object(**options)
      end

      destination = path_for(key)
      FileUtils.mkdir_p(destination.dirname)
      File.open(destination, "wb") { |file| IO.copy_stream(upload, file) }
    rescue Aws::S3::Errors::ServiceError, SystemCallError, IOError => error
      FileUtils.rm_f(destination) if destination
      raise WriteError, error.message
    end

    def delete(key)
      return if key.blank?
      return s3_client.delete_object(bucket: board_media_bucket, key:) if s3?

      FileUtils.rm_f(path_for(key))
    end

    def exist?(key)
      return s3_client.head_object(bucket: board_media_bucket, key:) && true if s3?

      path_for(key).file?
    rescue Aws::S3::Errors::NotFound
      false
    end

    def path_for(key)
      candidate = ROOT.join(key.to_s).cleanpath
      raise MissingFile, "Invalid board storage key" unless candidate.to_s.start_with?("#{ROOT}/")

      candidate
    end

    def public_url(key)
      return if key.blank? || board_media_cdn_url.blank?

      "#{board_media_cdn_url.chomp("/")}/#{escape_key(key)}"
    end

    def temporary_url(key, content_type: nil, disposition: nil)
      return unless s3? && key.present?

      options = { bucket: board_media_bucket, key:, expires_in: 15.minutes.to_i }
      options[:response_content_type] = content_type if content_type.present?
      options[:response_content_disposition] = disposition if disposition.present?
      Aws::S3::Presigner.new(client: s3_client).presigned_url(:get_object, **options)
    end

    # Preview responses stay on the authorized API origin. Redirecting a
    # credentialed image or video request to S3 makes the browser apply the
    # bucket's CORS policy to the final response, which is not the board access
    # boundary and causes previews to fail in the portal.
    def stream(key)
      return enum_for(__method__, key) unless block_given?

      if s3?
        s3_client.get_object(bucket: board_media_bucket, key:) { |chunk| yield chunk }
      else
        File.open(path_for(key), "rb") do |file|
          while (chunk = file.read(16 * 1024))
            yield chunk
          end
        end
      end
    rescue Aws::S3::Errors::NotFound
      raise MissingFile, "Board attachment is missing"
    end

    def s3?
      board_media_bucket.present?
    end

    private

    def board_media_bucket
      ENV["PROJECT_RED_BOARD_MEDIA_BUCKET"].presence
    end

    def board_media_cdn_url
      ENV["PROJECT_RED_BOARD_MEDIA_CDN_URL"].presence
    end

    def s3_client
      @s3_client ||= Aws::S3::Client.new(region: ENV.fetch("AWS_REGION", "us-west-2"))
    end

    def escape_key(key)
      key.to_s.split("/").map { |segment| URI::DEFAULT_PARSER.escape(segment) }.join("/")
    end
  end
end
