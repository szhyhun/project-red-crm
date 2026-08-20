module PricingPlans
  class Resolver
    def initialize(client_account:, product_variant:)
      @client_account = client_account
      @product_variant = product_variant
      @organization = client_account.organization
    end

    def price_cents
      direct_plan = @organization.pricing_plans.active.find_by(client_account: @client_account)
      return price_for(direct_plan) || @product_variant.price_cents if direct_plan

      team_plan = @organization.pricing_plans.active
                               .where(customer_team_id: @client_account.customer_team_ids)
                               .joins(:pricing_plan_prices)
                               .where(pricing_plan_prices: { product_variant_id: @product_variant.id })
                               .order(:priority, :id)
                               .first
      return price_for(team_plan) if team_plan

      @product_variant.price_cents
    end

    private

    def price_for(plan)
      plan&.pricing_plan_prices&.find_by(product_variant: @product_variant)&.price_cents
    end
  end
end
