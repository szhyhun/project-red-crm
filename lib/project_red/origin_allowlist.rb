require "uri"

module ProjectRed
  module OriginAllowlist
    module_function

    def crm_ui
      configured_origins(
        ENV["CRM_UI_ORIGINS"].presence || ENV["CRM_UI_ORIGIN"].presence || default_crm_ui_origin,
        setting: "CRM_UI_ORIGINS"
      )
    end

    def public_site
      value = ENV["PUBLIC_SITE_ORIGINS"].presence || ENV["PUBLIC_SITE_ORIGIN"].presence
      return [] if value.blank? && Rails.env.production?

      configured_origins(value.presence || "http://localhost:3000", setting: "PUBLIC_SITE_ORIGINS")
    end

    def configured_origins(value, setting:)
      value.to_s.split(",").map(&:strip).reject(&:empty?).map do |origin|
        normalize(origin, setting:)
      end.uniq
    end

    def normalize(origin, setting:)
      uri = URI.parse(origin)
      valid = %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.blank? &&
        [ "", "/" ].include?(uri.path.to_s) && uri.query.blank? && uri.fragment.blank?
      raise ArgumentError, "#{setting} contains an invalid origin: #{origin.inspect}" unless valid

      port = uri.port && !default_port?(uri) ? ":#{uri.port}" : ""
      "#{uri.scheme.downcase}://#{uri.host.downcase}#{port}"
    rescue URI::InvalidURIError => error
      raise ArgumentError, "#{setting} contains an invalid origin: #{origin.inspect} (#{error.message})"
    end

    def default_crm_ui_origin
      Rails.env.production? ? "https://crm.projectred.ca" : "http://localhost:3011"
    end

    def default_port?(uri)
      (uri.scheme == "http" && uri.port == 80) || (uri.scheme == "https" && uri.port == 443)
    end
  end
end
