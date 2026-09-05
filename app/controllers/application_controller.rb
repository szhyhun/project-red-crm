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
end
