require "fileutils"
require "securerandom"
require "aws-sdk-s3"

# Conversation files have their own storage boundary. They are private
# discussion material, so they never use the public listing-media CDN URL.
class ConversationStorage
  class MissingFile < StandardError; end
  class WriteError < StandardError; end

  ROOT = Rails.root.join("storage", "chat_media").freeze

  class << self
    def key_for(organization:, conversation:, message:, filename:)
      safe_filename = filename.to_s.parameterize.presence || "attachment"
      "organizations/#{organization.id}/conversations/#{conversation.id}/messages/#{message.id}/#{SecureRandom.uuid}-#{safe_filename}"
    end

    def write(upload:, key:, content_type: nil)
      if s3?
        options = { bucket: chat_media_bucket, key:, body: upload }
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
      return if key.blank?
      return s3_client.delete_object(bucket: chat_media_bucket, key:) if s3?

      FileUtils.rm_f(path_for(key))
    end

    def exist?(key)
      return s3_client.head_object(bucket: chat_media_bucket, key:) && true if s3?

      path_for(key).file?
    rescue Aws::S3::Errors::NotFound
      false
    end

    def path_for(key)
      candidate = ROOT.join(key.to_s).cleanpath
      raise MissingFile, "Invalid conversation storage key" unless candidate.to_s.start_with?("#{ROOT}/")

      candidate
    end

    def temporary_url(key, content_type: nil, disposition: nil)
      return unless s3? && key.present?

      options = { bucket: chat_media_bucket, key:, expires_in: 15.minutes.to_i }
      options[:response_content_type] = content_type if content_type.present?
      options[:response_content_disposition] = disposition if disposition.present?
      Aws::S3::Presigner.new(client: s3_client).presigned_url(:get_object, **options)
    end

    def stream(key)
      return enum_for(__method__, key) unless block_given?

      if s3?
        s3_client.get_object(bucket: chat_media_bucket, key:) { |chunk| yield chunk }
      else
        File.open(path_for(key), "rb") do |file|
          yield chunk while (chunk = file.read(16 * 1024))
        end
      end
    rescue Aws::S3::Errors::NotFound
      raise MissingFile, "Conversation attachment is missing"
    end

    def s3?
      chat_media_bucket.present?
    end

    private

    def chat_media_bucket
      ENV["PROJECT_RED_CHAT_MEDIA_BUCKET"].presence
    end

    def s3_client
      @s3_client ||= Aws::S3::Client.new(region: ENV.fetch("AWS_REGION", "us-west-2"))
    end
  end
end
