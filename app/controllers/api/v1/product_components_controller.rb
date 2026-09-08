class Api::V1::ProductComponentsController < Api::V1::BaseController
  before_action :set_product

  def index
    authorize @product, :view?
    render json: { components: @product.package_components.ordered.includes(:service_product).map { |component| serialize(component) } }
  end

  def create
    authorize @product, :update?
    service_product = policy_scope(Product).find(component_params.fetch(:service_product_id))
    component = @product.package_components.build(component_params.merge(
      organization: Current.organization, service_product:
    ))
    if component.save
      render json: { component: serialize(component.reload) }, status: :created
    else
      render_validation_errors(component)
    end
  end

  def update
    component = @product.package_components.find(params[:id])
    authorize @product, :update?
    attributes = component_params
    attributes[:service_product] = policy_scope(Product).find(attributes.delete(:service_product_id)) if attributes[:service_product_id].present?
    if component.update(attributes)
      render json: { component: serialize(component.reload) }
    else
      render_validation_errors(component)
    end
  end

  def destroy
    component = @product.package_components.find(params[:id])
    authorize @product, :update?
    component.destroy!
    head :no_content
  end

  private

  def set_product
    @product = policy_scope(Product).find(params[:product_id])
  end

  def component_params
    params.require(:product_component).permit(:service_product_id, :quantity, :position).to_h.symbolize_keys
  end

  def serialize(component)
    component.slice(:id, :quantity, :position).merge(
      package_product_id: component.package_product_id,
      service_product: component.service_product.slice(:id, :title, :kind, :deliverable_type, :sla_days)
    )
  end
end
