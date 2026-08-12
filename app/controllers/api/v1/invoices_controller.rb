class Api::V1::InvoicesController < Api::V1::BaseController
  def index
    invoices = policy_scope(Invoice).includes(:client_account, :listing, :order).order(created_at: :desc)
    invoices = invoices.where(listing_id: params[:listing_id]) if params[:listing_id].present?
    render json: { invoices: invoices.map { |invoice| serialize(invoice) } }
  end

  def create
    order = policy_scope(Order).find(invoice_params.fetch(:order_id))
    authorize order, :update?
    invoice = ::Invoices::Creator.new(organization: Current.organization, order: order).create!
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: invoice, event_type: "invoice.created")
    record_listing_activity(invoice, "invoice.created")
    render json: { invoice: serialize(invoice) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def send_invoice
    invoice = policy_scope(Invoice).find(params[:id])
    authorize invoice, :update?
    unless invoice.sendable?
      return render json: { error: "invoice_not_sendable", message: "Paid and void invoices cannot be sent." }, status: :unprocessable_entity
    end

    CustomerNotifications.invoice_ready(invoice)
    invoice.update!(status: invoice.draft? ? :sent : invoice.status, sent_at: Time.current)
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: invoice, event_type: "invoice.sent")
    record_listing_activity(invoice, "invoice.sent")
    render json: { invoice: serialize(invoice) }
  rescue CustomerNotifications::MissingRecipient => error
    render json: { error: "invoice_recipient_missing", message: error.message }, status: :unprocessable_entity
  end

  def send_reminder
    invoice = policy_scope(Invoice).find(params[:id])
    authorize invoice, :update?
    return render json: { error: "invoice_not_payable" }, status: :unprocessable_entity unless invoice.balance_due_cents.positive?

    CustomerNotifications.invoice_ready(invoice)
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: invoice, event_type: "invoice.reminder_sent")
    render json: { invoice: serialize(invoice) }
  rescue CustomerNotifications::MissingRecipient => error
    render json: { error: "invoice_recipient_missing", message: error.message }, status: :unprocessable_entity
  end

  def payment_intent
    invoice = policy_scope(Invoice).find(params[:id])
    authorize invoice, :pay?
    result = Payments::StripePaymentIntent.new(invoice:).create!

    render json: {
      payment: result.payment.slice(:id, :status, :amount_cents, :currency, :provider_payment_id),
      client_secret: result.client_secret
    }
  rescue Payments::StripePaymentIntent::PaymentUnavailable => error
    render json: { error: "payment_unavailable", message: error.message }, status: :unprocessable_entity
  rescue Stripe::StripeError => error
    render json: { error: "payment_provider_error", message: error.message }, status: :bad_gateway
  end

  private

  def invoice_params
    params.require(:invoice).permit(:order_id)
  end

  def serialize(invoice)
    invoice.slice(:id, :number, :status, :currency, :subtotal_cents, :discount_cents, :tax_cents, :fee_cents,
                  :fee_label, :total_cents, :balance_due_cents, :due_on, :sent_at).merge(
      client_account: invoice.client_account.slice(:id, :name),
      listing: invoice.listing && { id: invoice.listing.id, address: invoice.listing.address },
      order_id: invoice.order_id,
      can_pay: policy(invoice).pay?
    )
  end

  def record_listing_activity(invoice, event_type)
    listing = invoice.listing || invoice.order&.listing
    return unless listing

    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: listing, event_type:,
                          payload: { invoice_id: invoice.id, order_id: invoice.order_id })
  end
end
