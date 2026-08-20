class Api::V1::TravelFeesController < Api::V1::BaseController
  def index
    authorize TravelFee, :index?
    render json: { travel_fees: policy_scope(TravelFee).order(:name).map { |fee| serialize(fee) } }
  end

  def create
    fee = Current.organization.travel_fees.build(travel_fee_params)
    authorize fee
    fee.save!
    render json: { travel_fee: serialize(fee) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def update
    fee = policy_scope(TravelFee).find(params[:id])
    authorize fee
    fee.update!(travel_fee_params)
    render json: { travel_fee: serialize(fee) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def destroy
    fee = policy_scope(TravelFee).find(params[:id])
    authorize fee
    fee.destroy!
    head :no_content
  end

  private

  def travel_fee_params
    params.require(:travel_fee).permit(:name, :fee_type, :amount_cents, :rate_basis_points, :free_within_km, :active)
  end

  def serialize(fee)
    fee.slice(:id, :name, :fee_type, :amount_cents, :rate_basis_points, :free_within_km, :active)
  end
end
