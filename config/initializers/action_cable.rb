require Rails.root.join("lib/project_red/origin_allowlist").to_s

# The CRM and customer portal run on separate origins, so the websocket has the
# same credentialed allowlist as the API. Public property pages do not need an
# authenticated websocket and must not inherit the CRM session boundary.
Rails.application.config.action_cable.allowed_request_origins = ProjectRed::OriginAllowlist.crm_ui
