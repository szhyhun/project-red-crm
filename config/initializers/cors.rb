Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("CRM_UI_ORIGIN", "http://localhost:3001"), ENV.fetch("PUBLIC_SITE_ORIGIN", "http://localhost:3000")
    resource "/api/v1/*", headers: :any, methods: %i[get post patch put delete options], credentials: true
  end
end
