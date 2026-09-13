# Publishes policy answers to the client so the interface stops re-deriving
# authorization from the user's role. These are rendering hints: the server
# still authorizes every request on its own.
module Capabilities
  extend ActiveSupport::Concern

  # Resource types the session payload reports on. Each maps to the policy for
  # its model, asked at the class level.
  SESSION_RESOURCES = {
    boards: "Board",
    user_groups: "UserGroup",
    listings: "Listing",
    orders: "Order",
    invoices: "Invoice",
    products: "Product",
    client_accounts: "ClientAccount",
    conversations: "Conversation",
    media_assets: "MediaAsset",
    workflow_tasks: "WorkflowTask",
    workflow_columns: "WorkflowColumn",
    saved_listing_views: "SavedListingView",
    staff: "User",
    taxes: "Tax",
    coupons: "Coupon",
    travel_fees: "TravelFee",
    pricing_plans: "PricingPlan"
  }.freeze

  # These endpoints authorize a resource name rather than a persisted model.
  # Keep them in the same session payload without inventing database-backed
  # marker models solely for capability serialization.
  SESSION_HEADLESS_POLICIES = {
    dashboard: "DashboardPolicy",
    client_portal: "ClientPortalPolicy"
  }.freeze

  def capabilities_for(record)
    policy(record).capabilities
  end

  def session_capabilities(user)
    capabilities = SESSION_RESOURCES.each_with_object({}) do |(key, model_name), result|
      model = model_name.safe_constantize
      next result[key] = [] if model.blank?

      policy = Pundit::PolicyFinder.new(model).policy!.new(user, model)
      result[key] = policy.class::CAPABILITIES.filter_map do |capability|
        capability if policy.public_send(:"#{capability}?")
      rescue NoMethodError
        # A session answer is asked at the resource-class level, so policies
        # that need a concrete record cannot answer every question here. Keep
        # the role-level answers (for example BoardPolicy#create?) and omit
        # only the record-dependent question instead of losing the whole map.
        raise unless policy.record.is_a?(Class)
      end
    rescue Pundit::NotDefinedError, NameError
      result[key] = []
    end

    SESSION_HEADLESS_POLICIES.each do |key, policy_name|
      policy = policy_name.constantize.new(user, Object)
      capabilities[key] = policy.class::CAPABILITIES.filter_map do |capability|
        capability if policy.public_send(:"#{capability}?")
      end
    rescue Pundit::NotDefinedError, NameError
      capabilities[key] = []
    end

    capabilities
  end
end
