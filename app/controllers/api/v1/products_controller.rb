class Api::V1::ProductsController < Api::V1::BaseController
  def index
    products = policy_scope(Product).includes(:product_variants).order(:kind, :title)
    render json: { products: products.map { |product| serialize_product(product) } }
  end

  def show
    product = policy_scope(Product).includes(:product_variants).find(params[:id])
    authorize product
    render json: { product: serialize_product(product) }
  end

  private

  def serialize_product(product)
    {
      id: product.id,
      slug: product.slug,
      title: product.title,
      kind: product.kind,
      description: product.description,
      capabilities: product.capabilities,
      variants: product.product_variants.active.order(:price_cents).map do |variant|
        {
          id: variant.id,
          title: variant.title,
          price_cents: variant.price_cents,
          sqft_min: variant.sqft_min,
          sqft_max: variant.sqft_max,
          quantity_label: variant.quantity_label
        }
      end
    }
  end
end
