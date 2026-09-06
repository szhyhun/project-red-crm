# The portal runs on its own origin, so the websocket has the same allowlist the
# JSON API has. Without this every connection is refused as cross-origin.
Rails.application.config.action_cable.allowed_request_origins =
  ENV.fetch("CRM_UI_ORIGINS", ENV.fetch("CRM_UI_ORIGIN", "http://localhost:3011"))
     .split(",").map(&:strip).reject(&:empty?)
     .push(ENV.fetch("PUBLIC_SITE_ORIGIN", "http://localhost:3000"))
