class Rack::Attack
  throttle("api/ip", limit: 300, period: 5.minutes) do |request|
    request.ip if request.path.start_with?("/api/")
  end
end

Rails.application.config.middleware.use Rack::Attack
