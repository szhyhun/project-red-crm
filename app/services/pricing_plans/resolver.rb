module PricingPlans
  # What a product costs this customer, in the order Aryeo states on its own
  # screens: a price promised to the person beats any team they are on, a
  # team's plan beats the list price, and the list price is what is left.
  class Resolver
    def initialize(client_account:, product_variant:, user: nil)
      @client_account = client_account
      @product_variant = product_variant
      @user = user
      @organization = client_account.organization
    end

    def price_cents
      personal_plan = @user && @organization.pricing_plans.active.find_by(user: @user)
      personal_price = personal_plan && price_for(personal_plan)
      return personal_price if personal_price

      team_plan = @organization.pricing_plans.active.where(client_account: @client_account).order(:priority, :id).first
      price_for(team_plan) || @product_variant.price_cents
    end

    private

    def price_for(plan)
      plan&.pricing_plan_prices&.find_by(product_variant: @product_variant)&.price_cents
    end
  end
end
