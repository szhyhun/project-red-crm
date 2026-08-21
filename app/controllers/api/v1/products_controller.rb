class Api::V1::ProductsController < Api::V1::BaseController
  def index
    products = policy_scope(Product).includes(:product_variants).order(:kind, :title)
    render json: { products: products.map { |product| serialize_product(product) } }
  end

  def create
    product = Current.organization.products.build(product_params)
    authorize product

    if product.save
      render json: { product: serialize_product(product) }, status: :created
    else
      render_validation_errors(product)
    end
  end

  def update
    product = policy_scope(Product).find(params[:id])
    authorize product

    if product.update(product_params)
      render json: { product: serialize_product(product) }
    else
      render_validation_errors(product)
    end
  end

  def show
    product = policy_scope(Product).includes(:product_variants).find(params[:id])
    authorize product
    render json: { product: serialize_product(product) }
  end

  private

  def product_params
    params.require(:product).permit(:slug, :title, :kind, :description, :active, :bundle_candidate, :do_not_recommend,
                                    categories: [], capabilities: [], requires_capabilities: [],
                                    product_variants_attributes: %i[id title price_cents duration_minutes sqft_min sqft_max quantity_label active])
  end

  def serialize_product(product)
    {
      id: product.id,
      slug: product.slug,
      title: product.title,
      kind: product.kind,
      description: product.description,
      active: product.active,
      capabilities: product.capabilities,
      variants: product.product_variants.active.order(:price_cents).map do |variant|
        {
          id: variant.id,
          title: variant.title,
          price_cents: variant.price_cents,
          sqft_min: variant.sqft_min,
          sqft_max: variant.sqft_max,
          quantity_label: variant.quantity_label,
          duration_minutes: variant.duration_minutes
        }
      end
    }
  end
end
