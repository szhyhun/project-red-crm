class Api::V1::PricingPlansController < Api::V1::BaseController
  def index
    authorize PricingPlan, :index?
    plans = policy_scope(PricingPlan).includes(:client_account, :customer_team, :coupon, pricing_plan_prices: :product_variant).order(:name)
    render json: { pricing_plans: plans.map { |plan| serialize(plan) } }
  end

  def create
    plan = Current.organization.pricing_plans.build(pricing_plan_params)
    authorize plan
    plan.save!
    render json: { pricing_plan: serialize(plan) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def update
    plan = policy_scope(PricingPlan).find(params[:id])
    authorize plan
    plan.update!(pricing_plan_params)
    render json: { pricing_plan: serialize(plan) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def destroy
    plan = policy_scope(PricingPlan).find(params[:id])
    authorize plan
    plan.destroy!
    head :no_content
  end

  private

  def pricing_plan_params
    params.require(:pricing_plan).permit(:name, :client_account_id, :customer_team_id, :coupon_id, :priority, :active,
                                         pricing_plan_prices_attributes: %i[id product_variant_id price_cents _destroy])
  end

  def serialize(plan)
    plan.slice(:id, :name, :client_account_id, :customer_team_id, :coupon_id, :priority, :active).merge(
      pricing_plan_prices: plan.pricing_plan_prices.map { |price| price.slice(:id, :product_variant_id, :price_cents) }
    )
  end
end
