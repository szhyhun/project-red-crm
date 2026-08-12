class Api::V1::MarketingMaterialsController < Api::V1::BaseController
  before_action :set_listing

  def create
    material = @listing.marketing_materials.build(material_params.merge(organization: Current.organization, created_by: current_user))
    persist(material, :created)
  end

  def update
    persist(@listing.marketing_materials.find(params[:id]))
  end

  def destroy
    @listing.marketing_materials.find(params[:id]).update!(status: :archived)
    head :no_content
  end

  private

  def set_listing
    @listing = policy_scope(Listing).find(params[:listing_id])
    authorize @listing, :update?
  end

  def material_params
    params.require(:marketing_material).permit(:material_type, :title, :status, :customer_visible, settings: {})
  end

  def persist(material, status = :ok)
    if material.update(material_params)
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: @listing, event_type: "marketing_material.updated", payload: { id: material.id })
      render json: { marketing_material: material.slice(:id, :material_type, :title, :status, :customer_visible, :settings) }, status: status
    else
      render_validation_errors(material)
    end
  end
end
