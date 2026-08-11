class Api::V1::PropertySitesController < Api::V1::BaseController
  def show
    listing = policy_scope(Listing).find(params[:listing_id])
    site = policy_scope(PropertySite).find_by!(listing: listing)
    authorize site
    render json: { property_site: serialize(site) }
  end

  def create
    listing = policy_scope(Listing).find(params[:listing_id])
    site = listing.property_site || Current.organization.property_sites.build(listing: listing)
    authorize site

    if site.update(site_params)
      render json: { property_site: serialize(site) }, status: site.previously_new_record? ? :created : :ok
    else
      render_validation_errors(site)
    end
  end

  def update
    listing = policy_scope(Listing).find(params[:listing_id])
    site = policy_scope(PropertySite).find_by!(listing: listing)
    authorize site

    if site.update(site_params)
      render json: { property_site: serialize(site) }
    else
      render_validation_errors(site)
    end
  end

  def publish
    listing = policy_scope(Listing).find(params[:listing_id])
    site = policy_scope(PropertySite).find_by!(listing: listing)
    authorize site, :update?

    site.update!(status: :published, published_at: Time.current)
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: site, event_type: "property_site.published")
    render json: { property_site: serialize(site) }
  end

  private

  def site_params
    params.require(:property_site).permit(:slug, :custom_domain, settings: {})
  end

  def serialize(site)
    site.slice(:id, :listing_id, :slug, :status, :custom_domain, :published_at, :settings).merge(
      public_path: site.published? ? "/p/#{site.organization.slug}/#{site.slug}" : nil
    )
  end
end
