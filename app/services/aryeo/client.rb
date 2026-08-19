require "json"
require "net/http"

module Aryeo
  class Client
    class Error < StandardError; end
    class EndpointUnavailable < Error; end
    class ReadOnlyViolation < Error; end

    DEFAULT_BASE_URL = "https://api.aryeo.com/v1".freeze

    def initialize(api_key:, base_url: ENV.fetch("ARYEO_API_BASE_URL", DEFAULT_BASE_URL))
      @api_key = api_key
      @base_url = URI(base_url)
      raise Error, "Aryeo API key is missing" if @api_key.blank?
      raise Error, "Aryeo API URL must use HTTPS" unless @base_url.is_a?(URI::HTTPS)
    end

    def get(path, params: {})
      request(:get, path, params:)
    end

    # This guard is deliberate: migration code cannot accidentally mutate Aryeo.
    def request(method, path, params: {})
      raise ReadOnlyViolation, "Aryeo migration only permits GET requests" unless method.to_s.downcase == "get"

      uri = build_uri(path, params)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Accept"] = "application/json"

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 45) do |http|
        http.request(request)
      end

      return JSON.parse(response.body.presence || "{}") if response.is_a?(Net::HTTPSuccess)
      raise EndpointUnavailable, "#{path} is not available for this Aryeo account" if response.code.to_i == 404

      raise Error, "Aryeo GET #{path} failed with HTTP #{response.code}"
    rescue JSON::ParserError => error
      raise Error, "Aryeo returned invalid JSON: #{error.message}"
    end

    def paginate(path, params: {}, per_page: 100)
      page = 1
      request_path = path
      request_params = params.merge(page:, per_page:)
      loop do
        payload = get(request_path, params: request_params)
        records = Array(payload["data"] || payload["results"] || payload["items"])
        stop_requested = records.any? { |record| yield(record) == :stop }
        break if stop_requested

        pagination = payload["pagination"] || payload["meta"] || {}
        total_pages = pagination["total_pages"] || pagination["pages"]
        next_page = pagination["next_page"] || payload.dig("links", "next")
        break if records.empty? || (total_pages && page >= total_pages.to_i)

        if next_page.to_s.match?(%r{\A(?:https?://|/)})
          request_path = next_page
          request_params = {}
        elsif next_page.present?
          page = next_page.to_i
          page += 1 if page.zero?
          request_path = path
          request_params = params.merge(page:, per_page:)
        elsif total_pages && page < total_pages.to_i
          page += 1
          request_path = path
          request_params = params.merge(page:, per_page:)
        else
          break
        end
      end
    end

    private

    def build_uri(path, params)
      requested = URI(path.to_s)
      uri = requested.absolute? ? requested : @base_url.dup.tap { |base| base.path = "#{base.path.sub(%r{/$}, "")}/#{path.to_s.sub(%r{^/}, "")}" }
      raise Error, "Aryeo pagination link points outside the configured API host" unless uri.host == @base_url.host

      existing = URI.decode_www_form(uri.query.to_s)
      uri.query = URI.encode_www_form(existing + params.compact.to_a)
      uri
    end
  end
end
