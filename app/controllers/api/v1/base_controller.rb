class Api::V1::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :set_current_context

  private

  def set_current_context
    Current.user = current_user
    Current.organization = current_user.organization
  end

  def render_validation_errors(record)
    render json: { error: "validation_failed", details: record.errors.to_hash }, status: :unprocessable_entity
  end
end
