# frozen_string_literal: true

require "action_dispatch/middleware/session/cookie_store"
require_relative "origin_allowlist"

module ProjectRed
  # Keeps the CRM and customer portal sessions in separate encrypted cookies
  # while allowing both products to use the same API host.
  class SurfaceCookieStore < ActionDispatch::Session::CookieStore
    DEFAULT_PORTAL_KEY = "_project_red_portal_session"

    def initialize(app, options = {})
      @portal_key = options.delete(:portal_key) || DEFAULT_PORTAL_KEY
      super
    end

    private

    def set_cookie(request, _session_id, cookie)
      cookie_jar(request)[session_cookie_key(request)] = cookie
    end

    def get_cookie(request)
      cookie_jar(request)[session_cookie_key(request)]
    end

    def session_cookie_key(request)
      portal_request?(request) ? @portal_key : @key
    end

    def portal_request?(request)
      origin = request.get_header("HTTP_ORIGIN").to_s
      return false if origin.blank?

      normalized_origin = ProjectRed::OriginAllowlist.normalize(origin, setting: "CRM_UI_ORIGINS")
      return false unless ProjectRed::OriginAllowlist.crm_ui.include?(normalized_origin)

      URI.parse(normalized_origin).host.to_s.split(".").first == "portal"
    rescue ArgumentError, URI::InvalidURIError
      false
    end
  end
end
