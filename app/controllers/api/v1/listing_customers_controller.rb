class Api::V1::ListingCustomersController < Api::V1::BaseController
  before_action :set_listing

  def create
    customer = @listing.listing_customers.build(customer_params)
    if customer.save
      render json: { listing_customer: serialize(customer) }, status: :created
    else
      render_validation_errors(customer)
    end
  end

  def update
    customer = @listing.listing_customers.find(params[:id])
    if customer.update(customer_params)
      render json: { listing_customer: serialize(customer) }
    else
      render_validation_errors(customer)
    end
  end

  def destroy
    customer = @listing.listing_customers.find(params[:id])
    return render json: { error: "primary_customer_required" }, status: :unprocessable_entity if customer.primary?

    customer.destroy!
    head :no_content
  end

  private

  def set_listing
    @listing = policy_scope(Listing).find(params[:listing_id])
    authorize @listing, :update?
  end

  def customer_params
    params.require(:listing_customer).permit(:client_account_id, :primary, :marketing_visible)
  end

  def serialize(customer)
    customer.slice(:id, :client_account_id, :primary, :marketing_visible).merge(
      client_account: customer.client_account.slice(:id, :name, :email, :phone, :brokerage_name, :kind)
    )
  end
end
