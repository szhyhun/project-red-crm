class Api::V1::OrdersController < Api::V1::BaseController
  def index
    orders = policy_scope(Order).includes(:client_account, :listing, { invoices: :payments }, order_items: %i[product product_variant], order_deliverables: :service_product).order(created_at: :desc)
    orders = orders.where(listing_id: params[:listing_id]) if params[:listing_id].present?
    render json: { orders: orders.map { |order| serialize(order, include_details: true) } }
  end

  def show
    order = policy_scope(Order).includes(:client_account, :listing, order_items: %i[product product_variant], order_deliverables: :service_product, invoices: :payments).find(params[:id])
    authorize order
    render json: { order: serialize(order, include_details: true) }
  end

  def create
    authorize Order, :create?
    order = ::Orders::Creator.new(
      organization: Current.organization,
      attributes: create_params.to_h.deep_symbolize_keys,
      ordered_by: current_user
    ).create!
    render json: { order: serialize(order, include_details: true) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def update
    order = policy_scope(Order).find(params[:id])
    authorize order

    # Older approved orders may predate approved_at and deliverable
    # materialization. Keep PATCH approval on the same repairable path as the
    # canonical endpoint instead of silently treating that legacy state as
    # complete.
    if update_params[:status].to_s == "approved" && approval_service_required?(order)
      approve_order!(order)
      render json: { order: serialize(order.reload, include_details: true) }
      return
    end

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

  def approve
    order = policy_scope(Order).find(params[:id])
    authorize order, :update?
    approve_order!(order)
    render json: { order: serialize(order.reload, include_details: true) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
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

  # A specialist needs an order's items and deliverables to do the work, not
  # what the customer paid for it. Customers see their own order's money.
  ORDER_MONEY_KEYS = %i[payment_mode currency subtotal_cents discount_type discount_cents discount_rate_basis_points
                        tax_cents fee_cents fee_label total_cents payment_status balance_due_cents].freeze

  def billing_visible?
    !current_user.internal? || current_user.billing_access?
  end

  def serialize(order, include_details: false)
    data = order.slice(:id, :status, :fulfillment_status, :payment_mode, :currency, :subtotal_cents, :discount_type,
                       :discount_cents, :discount_rate_basis_points, :tax_cents, :fee_cents, :fee_label, :total_cents,
                       :tags, :approved_at, :created_at).merge(
      client_account: order.client_account.slice(:id, :name),
      listing: order.listing && { id: order.listing.id, address: order.listing.address },
      payment_status: order.payment_status,
      balance_due_cents: order.balance_due_cents
    )
    data = data.except(*ORDER_MONEY_KEYS) unless billing_visible?
    return data unless include_details

    details = {
      items: order.order_items.map { |item| serialize_item(item) },
      deliverables: order.order_deliverables.ordered.map { |deliverable| serialize_deliverable(deliverable) }
    }
    return data.merge(details) unless billing_visible?

    data.merge(details).merge(
      invoices: order.invoices.map do |invoice|
        invoice.slice(:id, :number, :status, :subtotal_cents, :discount_cents, :tax_cents, :fee_cents, :fee_label,
                      :total_cents, :balance_due_cents, :due_on, :sent_at, :paid_at).merge(
          can_pay: policy(invoice).pay?,
          payments: invoice.payments.order(created_at: :desc).map do |payment|
            payment.slice(:id, :provider, :status, :amount_cents, :currency, :created_at)
          end
        )
      end
    )
  end

  def serialize_item(item)
    data = item.slice(:id, :product_id, :product_variant_id, :title, :description, :options, :quantity,
                      :unit_price_cents, :total_cents, :cancelled_at).merge(
      product: item.product&.slice(:id, :title, :kind),
      product_variant: item.product_variant&.slice(:id, :title, :sqft_min, :sqft_max, :quantity_label)
    )
    billing_visible? ? data : data.except(:unit_price_cents, :total_cents)
  end

  def serialize_deliverable(deliverable)
    data = deliverable.slice(:id, :title, :description, :deliverable_type, :sla_days, :scope_sqft_min,
                             :scope_sqft_max, :scope_label, :status, :target_on, :delivered_at,
                             :delivery_version, :position, :cancelled_at).merge(
      asset_count: deliverable.customer_visible_assets.count
    )
    return data unless current_user.internal?

    data.merge(
      service_product: deliverable.service_product.slice(:id, :title, :deliverable_type),
      task_ids: deliverable.workflow_tasks.ids
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

  def approval_service_required?(order)
    !order.approved? || order.approved_at.blank? || order.order_deliverables.none?
  end

  def approve_order!(order)
    result = Orders::Approve.call(order:, actor: current_user)
    raise result.failure.original_error || result.failure if result.failure?
  end
end
