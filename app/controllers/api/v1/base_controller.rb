class Api::V1::BaseController < ApplicationController
  include Capabilities

  before_action :authenticate_user!
  before_action :set_current_context

  # Authorization is the default rather than something each action opts into.
  # `verify_authorized` reads a flag that `authorize` sets inside the action
  # body, so it can only run afterwards -- there is no before_action form of
  # this check. It is a programmer-error tripwire, not the security control:
  # the control is the `authorize` call it insists on.
  # Filtered with `if:` rather than `only: :index`, because Rails raises
  # ActionNotFound when an `only:` names an action a controller does not define
  # and most controllers here have no index.
  after_action :verify_authorized, unless: :index_action?
  after_action :verify_policy_scoped, if: :index_action?

  private

  def index_action?
    action_name == "index"
  end

  def set_current_context
    Current.user = current_user
    Current.organization = current_user.organization
  end

  def render_validation_errors(record)
    render json: { error: "validation_failed", details: record.errors.to_hash }, status: :unprocessable_entity
  end
end
