class ApplicationController < ActionController::API
  include ActionController::Cookies
  include ActionController::RequestForgeryProtection
  include Devise::Controllers::Helpers
  include Pundit::Authorization

  protect_from_forgery with: :exception
  self.allow_forgery_protection = false if Rails.env.test?

  # A denial names what was denied so the interface can say something useful
  # instead of showing a generic failure.
  rescue_from Pundit::NotAuthorizedError do |error|
    render json: {
      error: "forbidden",
      resource: error.record.is_a?(Class) ? error.record.name : error.record&.class&.name,
      action: error.query.to_s.delete_suffix("?").presence,
      message: "You don't have permission to do that."
    }.compact, status: :forbidden
  end

  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not_found" }, status: :not_found
  end

  # API clients can recover from an expired session token by requesting a new
  # one. Returning JSON keeps the browser from surfacing Rails' HTML exception
  # page and lets the client retry the rejected request exactly once.
  rescue_from ActionController::InvalidAuthenticityToken do
    render json: {
      error: "invalid_csrf_token",
      message: "Your secure session expired. Please retry."
    }, status: :unprocessable_content
  end
end
