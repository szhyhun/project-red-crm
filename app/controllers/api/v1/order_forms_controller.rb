class Api::V1::OrderFormsController < Api::V1::BaseController
  def index
    authorize OrderForm
    forms = policy_scope(OrderForm).includes(:order_form_products).order(:name)
    render json: { order_forms: forms.map { |form| serialize(form) } }
  end

  def create
    form = Current.organization.order_forms.build(order_form_params)
    authorize form
    if form.save
      render json: { order_form: serialize(form) }, status: :created
    else
      render_validation_errors(form)
    end
  end

  def update
    form = policy_scope(OrderForm).find(params[:id])
    authorize form
    if form.update(order_form_params)
      render json: { order_form: serialize(form.reload) }
    else
      render_validation_errors(form)
    end
  end

  def destroy
    form = policy_scope(OrderForm).find(params[:id])
    authorize form
    form.destroy!
    head :no_content
  end

  private

  def order_form_params
    params.require(:order_form).permit(:name, :description, :active, product_ids: [])
  end

  def serialize(form)
    form.slice(:id, :name, :description, :active).merge(
      product_ids: form.product_ids,
      team_count: form.client_accounts.count,
      capabilities: OrderFormPolicy.new(current_user, form).capabilities
    )
  end
end
