require Rails.root.join("lib/project_red/origin_allowlist").to_s

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*ProjectRed::OriginAllowlist.crm_ui)
    resource "/api/v1/*", headers: :any, methods: %i[get post patch put delete options], credentials: true
  end

  public_origins = ProjectRed::OriginAllowlist.public_site
  if public_origins.any?
    allow do
      origins(*public_origins)
      resource "/api/v1/public/*", headers: :any, methods: %i[get options], credentials: false
    end
  end
end
