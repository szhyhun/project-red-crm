class Api::V1::OrdersController < Api::V1::BaseController
  def index
    orders = policy_scope(Order).includes(:client_account, :listing, { invoices: :payments }, order_items: %i[product product_variant]).order(created_at: :desc)
    orders = orders.where(listing_id: params[:listing_id]) if params[:listing_id].present?
    render json: { orders: orders.map { |order| serialize(order, include_details: true) } }
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
      order.recalculate_totals!
      order.save! if order.changed?
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: order, event_type: "order.updated", payload: order.previous_changes)
      record_listing_activity(order, "order.updated")
      render json: { order: serialize(order, include_details: true) }
    else
      render_validation_errors(order)
    end
  end

  def cancel
    order = policy_scope(Order).find(params[:id])
    authorize order, :update?
    order.update!(status: :cancelled)
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: order, event_type: "order.cancelled")
    record_listing_activity(order, "order.cancelled")
    render json: { order: serialize(order, include_details: true) }
  end

  private

  def create_params
    params.require(:order).permit(:client_account_id, :listing_id, :payment_mode, :currency, :discount_type,
                                  :discount_cents, :discount_rate_basis_points, :tax_cents, :fee_cents, :fee_label,
                                  items: %i[product_variant_id quantity])
  end

  def update_params
    params.require(:order).permit(:status, :payment_mode, :fulfillment_status, :discount_type, :discount_cents,
                                  :discount_rate_basis_points, :tax_cents, :fee_cents, :fee_label, tags: [])
  end

  def serialize(order, include_details: false)
    data = order.slice(:id, :status, :fulfillment_status, :payment_mode, :currency, :subtotal_cents, :discount_type,
                       :discount_cents, :discount_rate_basis_points, :tax_cents, :fee_cents, :fee_label, :total_cents,
                       :tags, :created_at).merge(
      client_account: order.client_account.slice(:id, :name),
      listing: order.listing && { id: order.listing.id, address: order.listing.address },
      payment_status: order.payment_status,
      balance_due_cents: order.balance_due_cents
    )
    return data unless include_details

    data.merge(
      items: order.order_items.map { |item| serialize_item(item) },
      invoices: order.invoices.map do |invoice|
        invoice.slice(:id, :number, :status, :subtotal_cents, :discount_cents, :tax_cents, :fee_cents, :fee_label,
                      :total_cents, :balance_due_cents, :due_on, :sent_at, :paid_at).merge(
          can_pay: policy(invoice).pay?,
          payments: invoice.payments.order(created_at: :desc).map do |payment|
            payment.slice(:id, :provider, :provider_payment_id, :status, :amount_cents, :currency, :created_at)
          end
        )
      end
    )
  end

  def serialize_item(item)
    item.slice(:id, :product_id, :product_variant_id, :title, :description, :options, :quantity,
               :unit_price_cents, :total_cents, :cancelled_at).merge(
      product: item.product&.slice(:id, :title, :kind),
      product_variant: item.product_variant&.slice(:id, :title, :sqft_min, :sqft_max, :quantity_label)
    )
  end

  def record_listing_activity(order, event_type)
    return unless order.listing

    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: order.listing,
                          event_type: event_type, payload: {
                            order_id: order.id,
                            status: order.status,
                            payment_status: order.payment_status,
                            fulfillment_status: order.fulfillment_status,
                            total_cents: order.total_cents,
                            payment_mode: order.payment_mode
                          })
  end
end
