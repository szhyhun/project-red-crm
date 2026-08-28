class Api::V1::Public::PropertySitesController < ApplicationController
  def show
    organization = Organization.find_by!(slug: params[:organization_slug])
    site = organization.property_sites.published.includes(listing: :media_assets).find_by!(slug: params[:slug])
    assets = site.listing.media_assets.final.ready.order(:created_at)

    render json: {
      property_site: {
        slug: site.slug,
        settings: site.settings,
        listing: { address: site.listing.address, bedrooms: site.listing.bedrooms, bathrooms: site.listing.bathrooms, square_feet: site.listing.square_feet },
        media_assets: assets.map { |asset| serialize_asset(asset) }
      }
    }
  end

  private

  def serialize_asset(asset)
    {
      id: asset.id,
      filename: asset.filename,
      content_type: asset.content_type,
      storage_key: asset.storage_key,
      url: DeliveryStorage.public_url(asset.storage_key),
      metadata: asset.metadata
    }
  end
end
