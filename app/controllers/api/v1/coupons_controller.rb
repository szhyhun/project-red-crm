class Api::V1::CouponsController < Api::V1::BaseController
  def index
    authorize Coupon, :index?
    render json: { coupons: policy_scope(Coupon).order(:code).map { |coupon| serialize(coupon) } }
  end

  def create
    coupon = Current.organization.coupons.build(coupon_params)
    authorize coupon
    coupon.save!
    render json: { coupon: serialize(coupon) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def update
    coupon = policy_scope(Coupon).find(params[:id])
    authorize coupon
    coupon.update!(coupon_params)
    render json: { coupon: serialize(coupon) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def destroy
    coupon = policy_scope(Coupon).find(params[:id])
    authorize coupon
    coupon.destroy!
    head :no_content
  end

  private

  def coupon_params
    params.require(:coupon).permit(:code, :description, :discount_type, :amount_cents, :rate_basis_points,
                                   :starts_at, :ends_at, :max_redemptions, :active)
  end

  def serialize(coupon)
    coupon.slice(:id, :code, :description, :discount_type, :amount_cents, :rate_basis_points,
                 :starts_at, :ends_at, :max_redemptions, :redemption_count, :active)
  end
end
