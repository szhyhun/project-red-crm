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

  def upload
    listing = policy_scope(Listing).find(params.require(:listing_id))
    authorize MediaAsset, :create?
    uploaded_file = params.require(:file)
    storage_key = DeliveryStorage.key_for(organization: Current.organization, listing: listing, filename: uploaded_file.original_filename)
    asset = Current.organization.media_assets.build(
      listing: listing,
      uploaded_by: current_user,
      kind: params.fetch(:kind, "final"),
      status: :pending,
      storage_key: storage_key,
      filename: uploaded_file.original_filename,
      content_type: uploaded_file.content_type.presence || "application/octet-stream",
      byte_size: uploaded_file.size
    )

    if asset.save
      DeliveryStorage.write(upload: uploaded_file.tempfile, key: storage_key)
      MediaAssets::VerifyUploadJob.perform_later(asset.id)
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: asset, event_type: "media_asset.uploaded")
      render json: { media_asset: serialize(asset) }, status: :created
    else
      render_validation_errors(asset)
    end
  rescue DeliveryStorage::MissingFile, DeliveryStorage::WriteError => error
    DeliveryStorage.delete(storage_key) if storage_key.present?
    asset&.update(status: :failed, metadata: asset.metadata.merge("processing_error" => error.message))
    render json: { error: "upload_failed" }, status: :unprocessable_entity
  end

  def download
    asset = policy_scope(MediaAsset).find(params[:id])
    authorize asset, :show?
    return render json: { error: "asset_not_ready" }, status: :unprocessable_entity unless asset.ready?

    send_file DeliveryStorage.path_for(asset.storage_key), type: "application/octet-stream", disposition: "attachment", filename: asset.filename
  rescue DeliveryStorage::MissingFile
    render json: { error: "asset_missing" }, status: :not_found
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
      cdn_url: asset.ready? ? cdn_url_for(asset.storage_key) : nil,
      download_path: asset.ready? ? download_api_v1_media_asset_path(asset) : nil,
      uploaded_by: asset.uploaded_by && asset.uploaded_by.slice(:id, :name)
    )
  end

  def cdn_url_for(storage_key)
    cdn_base = ENV["MEDIA_CDN_URL"]
    return nil if cdn_base.blank?

    "#{cdn_base.chomp("/")}/#{URI::DEFAULT_PARSER.escape(storage_key)}"
  end
end
