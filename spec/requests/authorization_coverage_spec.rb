require "rails_helper"

# The verify_authorized callback catches a forgotten `authorize` at runtime, but
# only for controllers that inherit it. A controller that inherits
# ApplicationController directly opts out of the whole mechanism silently, which
# is exactly what the four unauthenticated endpoints below do on purpose.
#
# This is the pre-deploy half of that guarantee: any new API controller either
# inherits the enforced base or is named here deliberately.
RSpec.describe "Authorization coverage", type: :request do
  # Endpoints that legitimately run without an authenticated organization user.
  UNAUTHENTICATED_CONTROLLERS = %w[
    api/v1/auth/sessions
    api/v1/auth/registrations
    api/v1/public/property_sites
    api/v1/webhooks/stripe
  ].freeze

  def api_controllers
    Rails.application.routes.routes
      .filter_map { |route| route.defaults[:controller] }
      .select { |controller| controller.start_with?("api/") }
      .uniq
      .sort
  end

  it "routes every API endpoint through the enforced base controller" do
    unenforced = api_controllers.reject do |name|
      next true if UNAUTHENTICATED_CONTROLLERS.include?(name)

      "#{name}_controller".camelize.constantize <= Api::V1::BaseController
    end

    expect(unenforced).to be_empty,
      "these controllers bypass verify_authorized: #{unenforced.join(', ')}. " \
      "Inherit Api::V1::BaseController, or add the controller to " \
      "UNAUTHENTICATED_CONTROLLERS with a reason."
  end

  it "keeps the allowlist honest by failing when a listed controller disappears" do
    expect(UNAUTHENTICATED_CONTROLLERS - api_controllers).to be_empty
  end

  it "answers the same question set on every policy" do
    policies = Dir[Rails.root.join("app/policies/*_policy.rb")]
      .map { |path| File.basename(path, ".rb").camelize.constantize }
      .reject { |policy| policy == ApplicationPolicy }

    missing = policies.reject { |policy| policy.instance_method(:capabilities) }
    expect(missing).to be_empty
    expect(policies).to all(be < ApplicationPolicy)
  end
end
