class Api::V1::OrderItemsController < Api::V1::BaseController
  before_action :set_order

  def create
    attributes = item_params.to_h.symbolize_keys
    variant_id = attributes.delete(:product_variant_id)
    item = if variant_id.present?
      variant = find_variant(variant_id)
      quantity = Integer(attributes.fetch(:quantity, 1))
      @order.order_items.build(
        product: variant.product,
        product_variant: variant,
        title: [variant.product.title, variant.title].compact.join(" - "),
        description: variant.product.description,
        quantity: quantity,
        unit_price_cents: variant.price_cents,
        total_cents: variant.price_cents * quantity,
        options: attributes[:options] || {},
        snapshot: {
          product_title: variant.product.title,
          variant_title: variant.title,
          price_cents: variant.price_cents
        }
      )
    else
      @order.order_items.build(attributes)
    end
    item.total_cents = item.unit_price_cents * item.quantity
    persist(item, :created)
  rescue ArgumentError, TypeError
    render json: { error: "invalid_quantity" }, status: :unprocessable_entity
  end

  def update
    item = @order.order_items.find(params[:id])
    item.assign_attributes(update_params)
    item.total_cents = item.unit_price_cents * item.quantity
    persist(item)
  end

  def destroy
    item = @order.order_items.find(params[:id])
    item.update!(cancelled_at: Time.current)
    finish("order_item.cancelled", item)
    render json: { order_item: serialize(item) }
  end

  private

  def set_order
    @order = policy_scope(Order).find(params[:order_id])
    authorize @order, :update?
  end

  def item_params
    params.require(:order_item).permit(:product_variant_id, :title, :description, :quantity, :unit_price_cents, options: {})
  end

  def update_params
    params.require(:order_item).permit(:title, :description, :quantity, :unit_price_cents, options: {})
  end

  def find_variant(id)
    ProductVariant.joins(:product)
                  .where(products: { organization_id: Current.organization.id, active: true })
                  .merge(ProductVariant.active)
                  .find(id)
  end

  def persist(item, status = :ok)
    if item.save
      finish("order_item.#{status == :created ? 'created' : 'updated'}", item)
      render json: { order_item: serialize(item) }, status: status
    else
      render_validation_errors(item)
    end
  end

  def finish(event_type, item)
    @order.recalculate_totals!
    @order.save!
    payload = {
      order_id: @order.id,
      order_item_id: item.id,
      title: item.title,
      quantity: item.quantity,
      total_cents: item.total_cents,
      cancelled: item.cancelled_at.present?
    }
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: @order,
                          event_type: event_type, payload: payload)
    if @order.listing
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: @order.listing,
                            event_type: event_type, payload: payload)
    end
  end

  def serialize(item)
    item.slice(:id, :product_id, :product_variant_id, :title, :description, :options, :quantity, :unit_price_cents, :total_cents, :cancelled_at)
  end
end
