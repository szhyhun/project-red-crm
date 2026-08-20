class Api::V1::TaxesController < Api::V1::BaseController
  def index
    authorize Tax, :index?
    render json: { taxes: policy_scope(Tax).order(:name).map { |tax| serialize(tax) } }
  end

  def create
    tax = Current.organization.taxes.build(tax_params)
    authorize tax
    tax.save!
    render json: { tax: serialize(tax) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def update
    tax = policy_scope(Tax).find(params[:id])
    authorize tax
    tax.update!(tax_params)
    render json: { tax: serialize(tax) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def destroy
    tax = policy_scope(Tax).find(params[:id])
    authorize tax
    tax.destroy!
    head :no_content
  end

  private

  def tax_params
    params.require(:tax).permit(:name, :rate_basis_points, :scope, :active)
  end

  def serialize(tax)
    tax.slice(:id, :name, :rate_basis_points, :scope, :active)
  end
end
