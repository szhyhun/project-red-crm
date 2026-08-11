class Api::V1::OrdersController < Api::V1::BaseController
  def index
    orders = policy_scope(Order).includes(:client_account, :listing, order_items: %i[product product_variant]).order(created_at: :desc)
    orders = orders.where(listing_id: params[:listing_id]) if params[:listing_id].present?
    render json: { orders: orders.map { |order| serialize(order) } }
  end

  def show
    order = policy_scope(Order).includes(:client_account, :listing, order_items: %i[product product_variant], invoices: :payments).find(params[:id])
    authorize order
    render json: { order: serialize(order, include_details: true) }
  end

  def create
    authorize Order, :create?
    order = ::Orders::Creator.new(organization: Current.organization, attributes: create_params.to_h.deep_symbolize_keys).create!
    render json: { order: serialize(order, include_details: true) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def update
    order = policy_scope(Order).find(params[:id])
    authorize order

    if order.update(update_params)
      render json: { order: serialize(order, include_details: true) }
    else
      render_validation_errors(order)
    end
  end

  private

  def create_params
    params.require(:order).permit(:client_account_id, :listing_id, :payment_mode, :currency, :discount_cents, :tax_cents,
                                  items: %i[product_variant_id quantity])
  end

  def update_params
    params.require(:order).permit(:status, :payment_mode)
  end

  def serialize(order, include_details: false)
    data = order.slice(:id, :status, :payment_mode, :currency, :subtotal_cents, :discount_cents, :tax_cents, :total_cents, :created_at).merge(
      client_account: order.client_account.slice(:id, :name),
      listing: order.listing && { id: order.listing.id, address: order.listing.address }
    )
    return data unless include_details

    data.merge(
      items: order.order_items.map { |item| item.slice(:id, :title, :quantity, :unit_price_cents, :total_cents) },
      invoices: order.invoices.map { |invoice| invoice.slice(:id, :number, :status, :total_cents, :balance_due_cents, :due_on) }
    )
  end
end
