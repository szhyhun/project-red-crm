require "ipaddr"
require "net/http"
require "resolv"
require "tempfile"
require "uri"

module Aryeo
  class RemoteMediaCopy
    class RetryableError < StandardError; end

    Download = Struct.new(:io, :content_type, keyword_init: true)
    MAX_REDIRECTS = 3

    BLOCKED_NETWORKS = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16
      198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ::/128 ::1/128 fc00::/7 fe80::/10
    ].map { |network| IPAddr.new(network) }.freeze

    def self.call(asset:, source_url:, api_key: nil)
      download = fetch_media(source_url, api_key:)
      DeliveryStorage.write(upload: download.io, key: asset.storage_key,
                            content_type: download.content_type.presence || asset.content_type)
      asset.update!(status: :ready, processed_at: Time.current, source_url: nil,
                    metadata: asset.metadata.merge("aryeo_source_url" => source_url).except("processing_error"))
    rescue RetryableError
      raise
    rescue Net::HTTPError, SocketError, Timeout::Error, EOFError, IOError, SystemCallError, DeliveryStorage::WriteError => error
      raise RetryableError, "Aryeo media copy failed: #{error.class}"
    ensure
      download&.io&.close!
    end

    def self.allowed_uri(source_url)
      raise RetryableError, "Missing Aryeo media URL" if source_url.blank?

      uri = URI.parse(source_url)
      addresses = Resolv.getaddresses(uri.host.to_s)
      allowed = uri.is_a?(URI::HTTPS) && uri.userinfo.blank? && uri.host.present? && addresses.present? &&
        addresses.none? { |address| blocked_address?(address) }
      raise RetryableError, "Aryeo media URL is not allowed" unless allowed

      uri
    rescue URI::InvalidURIError, Resolv::ResolvError, SocketError
      raise RetryableError, "Aryeo media URL is not allowed"
    end

    def self.blocked_address?(address)
      ip = IPAddr.new(address)
      ip.loopback? || ip.link_local? || ip.private? || BLOCKED_NETWORKS.any? { |network| network.include?(ip) }
    end

    def self.fetch_media(source_url, api_key:, redirects_left: MAX_REDIRECTS)
      uri = allowed_uri(source_url)
      response = nil
      tempfile = nil
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "*/*"
      request["Authorization"] = "Bearer #{api_key}" if api_key.present? && aryeo_media_host?(uri.host)

      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 120) do |http|
        http.request(request) do |candidate|
          response = candidate
          next unless candidate.is_a?(Net::HTTPSuccess)

          tempfile = Tempfile.new([ "aryeo-media", File.extname(uri.path).presence || ".bin" ])
          candidate.read_body { |chunk| tempfile.write(chunk) }
          tempfile.rewind
        end
      end

      if response.is_a?(Net::HTTPSuccess)
        return Download.new(io: tempfile, content_type: response["content-type"].to_s.split(";").first.presence)
      end

      tempfile&.close!
      if response.is_a?(Net::HTTPRedirection)
        raise RetryableError, "Aryeo media redirect limit reached" if redirects_left.zero?

        location = response["location"].presence
        raise RetryableError, "Aryeo media redirect has no location" if location.blank?

        redirected_uri = URI.join(uri.to_s, location).to_s
        return fetch_media(redirected_uri, api_key:, redirects_left: redirects_left - 1)
      end

      raise RetryableError, "Aryeo media download returned HTTP #{response&.code || "unknown"}"
    rescue RetryableError
      tempfile&.close!
      raise
    rescue URI::InvalidURIError
      tempfile&.close!
      raise RetryableError, "Aryeo media redirect is not allowed"
    rescue Net::HTTPError, SocketError, Timeout::Error, EOFError, IOError, SystemCallError
      tempfile&.close!
      raise
    end

    def self.aryeo_media_host?(host)
      host == "aryeo.com" || host.to_s.end_with?(".aryeo.com")
    end

    private_class_method :fetch_media, :aryeo_media_host?
  end
end
