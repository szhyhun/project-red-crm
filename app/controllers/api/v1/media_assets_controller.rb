class Api::V1::MediaAssetsController < Api::V1::BaseController
  def index
    assets = policy_scope(MediaAsset).includes(:listing, :uploaded_by).order(created_at: :desc)
    assets = assets.where(listing_id: params[:listing_id]) if params[:listing_id].present?
    authorize MediaAsset, :index?
    render json: { media_assets: assets.map { |asset| serialize(asset) } }
  end

  def create
    listing = policy_scope(Listing).find(create_params.fetch(:listing_id))
    asset = Current.organization.media_assets.build(create_params.merge(listing: listing, uploaded_by: current_user))
    authorize asset

    if asset.save
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: asset, event_type: "media_asset.registered")
      render json: { media_asset: serialize(asset) }, status: :created
    else
      render_validation_errors(asset)
    end
  end

  def update
    asset = policy_scope(MediaAsset).find(params[:id])
    authorize asset

    if asset.update(update_params)
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: asset, event_type: "media_asset.updated")
      render json: { media_asset: serialize(asset) }
    else
      render_validation_errors(asset)
    end
  end

  private

  def create_params
    params.require(:media_asset).permit(
      :listing_id, :kind, :status, :storage_key, :filename, :content_type, :byte_size,
      :width, :height, :duration_seconds, metadata: {}
    )
  end

  def update_params
    params.require(:media_asset).permit(:kind, :status, :filename, :content_type, :byte_size,
                                        :width, :height, :duration_seconds, metadata: {})
  end

  def serialize(asset)
    asset.slice(:id, :listing_id, :kind, :status, :storage_key, :filename, :content_type,
                :byte_size, :width, :height, :duration_seconds, :metadata, :processed_at, :created_at).merge(
      cdn_url: cdn_url_for(asset.storage_key),
      uploaded_by: asset.uploaded_by && asset.uploaded_by.slice(:id, :name)
    )
  end

  def cdn_url_for(storage_key)
    cdn_base = ENV["MEDIA_CDN_URL"]
    return nil if cdn_base.blank?

    "#{cdn_base.chomp("/")}/#{URI::DEFAULT_PARSER.escape(storage_key)}"
  end
end
