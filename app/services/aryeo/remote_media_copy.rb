require "open-uri"
require "ipaddr"
require "resolv"
require "tempfile"

module Aryeo
  class RemoteMediaCopy
    class RetryableError < StandardError; end

    BLOCKED_NETWORKS = %w[
      0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16
      172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.168.0.0/16
      198.18.0.0/15 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4
      ::/128 ::1/128 fc00::/7 fe80::/10
    ].map { |network| IPAddr.new(network) }.freeze

    def self.call(asset:, source_url:)
      uri = allowed_uri(source_url)

      URI.open(uri.to_s, open_timeout: 15, read_timeout: 120, redirect: false, max_redirects: 0) do |remote|
        DeliveryStorage.write(upload: remote, key: asset.storage_key)
      end
      asset.update!(status: :ready, processed_at: Time.current, source_url: nil,
                    metadata: asset.metadata.merge("aryeo_source_url" => source_url).except("processing_error"))
    rescue RetryableError
      raise
    rescue OpenURI::HTTPError, OpenURI::HTTPRedirect, SocketError, Timeout::Error, IOError, DeliveryStorage::WriteError => error
      raise RetryableError, "Aryeo media copy failed: #{error.class}"
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
  end
end
