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
    render json: { invoice: serialize(invoice) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  private

  def invoice_params
    params.require(:invoice).permit(:order_id)
  end

  def serialize(invoice)
    invoice.slice(:id, :number, :status, :currency, :subtotal_cents, :tax_cents, :total_cents, :balance_due_cents, :due_on, :sent_at).merge(
      client_account: invoice.client_account.slice(:id, :name),
      listing: invoice.listing && { id: invoice.listing.id, address: invoice.listing.address },
      order_id: invoice.order_id
    )
  end
end
