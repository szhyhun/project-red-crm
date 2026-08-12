class Api::V1::ListingCustomFieldsController < Api::V1::BaseController
  before_action :set_listing

  def create
    field = @listing.listing_custom_fields.build(field_params)
    persist(field, :created)
  end

  def update
    persist(@listing.listing_custom_fields.find(params[:id]))
  end

  def destroy
    @listing.listing_custom_fields.find(params[:id]).destroy!
    head :no_content
  end

  private

  def set_listing
    @listing = policy_scope(Listing).find(params[:listing_id])
    authorize @listing, :update?
  end

  def field_params
    params.require(:listing_custom_field).permit(:name, :value, :position)
  end

  def persist(field, status = :ok)
    if field.update(field_params)
      render json: { listing_custom_field: field.slice(:id, :name, :value, :position) }, status: status
    else
      render_validation_errors(field)
    end
  end
end
