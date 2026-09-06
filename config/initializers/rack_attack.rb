require "digest"

class Rack::Attack
  # Development and test drive the whole portal from a single IP, and opening one
  # listing with a large media library can spend a few hundred requests by
  # itself, so the local ceiling is much higher than the production one.
  LIMIT = Rails.env.local? ? 1500 : 300
  PERIOD = 5.minutes
  AUTH_SIGN_IN_LIMIT = ENV.fetch("AUTH_SIGN_IN_LIMIT", 10).to_i
  AUTH_SIGN_IN_PERIOD = 15.minutes

  # Keyed per signed-in user rather than per IP: an agency behind one office
  # address would otherwise share a single budget between everyone working that
  # day. Anonymous traffic still falls back to the IP so sign-in and the public
  # property-site endpoints stay covered.
  throttle("api/client", limit: LIMIT, period: PERIOD) do |request|
    next unless request.path.start_with?("/api/")

    Rack::Attack.throttle_key_for(request)
  end

  # Keep credential guessing from consuming the much larger general API budget.
  # The email key is hashed so a throttle key never becomes a credential or an
  # email address in a shared cache or log message.
  throttle("auth/sign_in/ip", limit: AUTH_SIGN_IN_LIMIT, period: AUTH_SIGN_IN_PERIOD) do |request|
    next unless request.request_method == "POST" && request.path == "/api/v1/auth/sign_in"

    "ip:#{request.ip}"
  end

  throttle("auth/sign_in/email", limit: AUTH_SIGN_IN_LIMIT, period: AUTH_SIGN_IN_PERIOD) do |request|
    next unless request.request_method == "POST" && request.path == "/api/v1/auth/sign_in"

    email = request.params["email"].to_s.downcase.strip
    next if email.blank?

    "email:#{Digest::SHA256.hexdigest(email)}"
  end

  # Reads the Warden session key directly instead of asking Warden for the user,
  # which would deserialize the record and add a query to every request.
  def self.throttle_key_for(request)
    user_id = Array(session_user_key(request)&.first).first
    user_id ? "user:#{user_id}" : "ip:#{request.ip}"
  end

  def self.session_user_key(request)
    session = request.env["rack.session"]
    session && session["warden.user.user.key"]
  rescue StandardError
    nil
  end
end

# The rack-attack railtie already inserts the middleware. Adding it again here
# put two identical instances in the stack, and each one incremented the same
# throttle counter, so every request was billed twice and the effective ceiling
# was half of LIMIT.
