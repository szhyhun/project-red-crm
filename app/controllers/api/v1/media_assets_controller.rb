class Api::V1::MediaAssetsController < Api::V1::BaseController
  def index
    assets = policy_scope(MediaAsset).includes(:listing, :uploaded_by, :order, :order_item).order(:category, :position, :created_at)
    assets = assets.where(listing_id: params[:listing_id]) if params[:listing_id].present?
    authorize MediaAsset, :index?
    render json: { media_assets: assets.map { |asset| serialize(asset) } }
  end

  def create
    listing = policy_scope(Listing).find(create_params.fetch(:listing_id))
    asset = Current.organization.media_assets.build(create_params.except(:order_id, :order_item_id).merge(
      listing: listing,
      uploaded_by: current_user,
      **source_records
    ))
    authorize asset

    if asset.save
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: asset, event_type: "media_asset.registered")
      record_listing_activity(asset, "media_asset.registered", media_payload(asset))
      render json: { media_asset: serialize(asset) }, status: :created
    else
      render_validation_errors(asset)
    end
  end

  def upload
    listing = policy_scope(Listing).find(params.require(:listing_id))
    authorize MediaAsset, :create?
    files = Array(params[:files]).presence || [ params.require(:file) ]
    assets = files.map { |uploaded_file| upload_one(listing, uploaded_file) }
    render json: { media_assets: assets.map { |asset| serialize(asset) }, media_asset: assets.first }, status: :created
  rescue DeliveryStorage::MissingFile, DeliveryStorage::WriteError => error
    render json: { error: "upload_failed", details: error.message }, status: :unprocessable_entity
  end

  def link
    listing = policy_scope(Listing).find(params.require(:listing_id))
    authorize MediaAsset, :create?
    asset = Current.organization.media_assets.build(link_params.merge(
      listing: listing,
      uploaded_by: current_user,
      kind: params.fetch(:kind, "final"),
      status: :ready,
      storage_key: nil,
      **source_records
    ))

    if asset.save
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: asset, event_type: "media_asset.linked")
      record_listing_activity(asset, "media_asset.linked", media_payload(asset))
      render json: { media_asset: serialize(asset) }, status: :created
    else
      render_validation_errors(asset)
    end
  end

  def reorder
    listing = policy_scope(Listing).find(params.require(:listing_id))
    authorize listing, :update?
    category = params.require(:category)
    asset_ids = Array(params.require(:asset_ids)).map(&:to_i)
    raise ActiveRecord::RecordNotFound unless asset_ids.present? && asset_ids == asset_ids.uniq
    assets = listing.media_assets.where(category: category).where(id: asset_ids).index_by(&:id)
    raise ActiveRecord::RecordNotFound unless assets.size == asset_ids.size

    MediaAsset.transaction do
      asset_ids.each_with_index { |asset_id, position| assets.fetch(asset_id).update!(position: position) }
    end
    render json: { media_assets: listing.media_assets.where(category: category).order(:position, :created_at).map { |asset| serialize(asset) } }
  end

  def replace
    asset = policy_scope(MediaAsset).find(params[:id])
    authorize asset, :update?
    uploaded_file = params.require(:file)
    old_key = asset.storage_key
    new_key = DeliveryStorage.key_for(organization: Current.organization, listing: asset.listing, filename: uploaded_file.original_filename)

    DeliveryStorage.write(upload: uploaded_file.tempfile, key: new_key)
    asset.update!(
      status: :pending,
      storage_key: new_key,
      filename: uploaded_file.original_filename,
      content_type: uploaded_file.content_type.presence || "application/octet-stream",
      byte_size: uploaded_file.size,
      processed_at: nil,
      metadata: asset.metadata.except("processing_error")
    )
    DeliveryStorage.delete(old_key) if old_key.present? && old_key != new_key
    MediaAssets::VerifyUploadJob.perform_later(asset.id)
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: asset, event_type: "media_asset.replaced")
    record_listing_activity(asset, "media_asset.replaced", media_payload(asset))
    render json: { media_asset: serialize(asset) }
  rescue DeliveryStorage::MissingFile, DeliveryStorage::WriteError => error
    DeliveryStorage.delete(new_key) if defined?(new_key) && new_key.present?
    render json: { error: "replace_failed", details: error.message }, status: :unprocessable_entity
  end

  def retry
    asset = policy_scope(MediaAsset).find(params[:id])
    authorize asset, :update?
    asset.update!(status: :pending, metadata: asset.metadata.except("processing_error"), processed_at: nil)
    MediaAssets::VerifyUploadJob.perform_later(asset.id)
    render json: { media_asset: serialize(asset) }
  end

  def upload_one(listing, uploaded_file)
    storage_key = DeliveryStorage.key_for(organization: Current.organization, listing: listing, filename: uploaded_file.original_filename)
    category = requested_category(uploaded_file)
    asset = Current.organization.media_assets.build(
      listing: listing,
      uploaded_by: current_user,
      kind: params.fetch(:kind, "final"),
      category: category,
      position: listing.media_assets.where(category: category).maximum(:position).to_i + 1,
      customer_visible: ActiveModel::Type::Boolean.new.cast(params.fetch(:customer_visible, true)),
      status: :pending,
      storage_key: storage_key,
      filename: uploaded_file.original_filename,
      content_type: uploaded_file.content_type.presence || "application/octet-stream",
      byte_size: uploaded_file.size,
      **source_records
    )

    if asset.save
      DeliveryStorage.write(upload: uploaded_file.tempfile, key: storage_key)
      MediaAssets::VerifyUploadJob.perform_later(asset.id)
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: asset, event_type: "media_asset.uploaded")
      record_listing_activity(asset, "media_asset.uploaded", media_payload(asset))
      asset
    else
      raise ActiveRecord::RecordInvalid, asset
    end
  rescue DeliveryStorage::MissingFile, DeliveryStorage::WriteError => error
    DeliveryStorage.delete(storage_key) if storage_key.present?
    asset&.update(status: :failed, metadata: asset.metadata.merge("processing_error" => error.message))
    raise
  end

  def download
    asset = policy_scope(MediaAsset).find(params[:id])
    authorize asset, :show?
    return redirect_to asset.source_url, allow_other_host: true if asset.external? && asset.ready?
    return render json: { error: "asset_not_ready" }, status: :unprocessable_entity unless asset.ready?

    send_file DeliveryStorage.path_for(asset.storage_key), type: "application/octet-stream", disposition: "attachment", filename: asset.filename
  rescue DeliveryStorage::MissingFile
    render json: { error: "asset_missing" }, status: :not_found
  end

  def update
    asset = policy_scope(MediaAsset).find(params[:id])
    authorize asset

    if asset.update(update_params)
      if asset.cover?
        asset.listing&.media_assets&.where(category: asset.category)&.where.not(id: asset.id)&.update_all(cover: false)
      end
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: asset, event_type: "media_asset.updated")
      record_listing_activity(asset, "media_asset.updated", filename: asset.filename)
      render json: { media_asset: serialize(asset) }
    else
      render_validation_errors(asset)
    end
  end

  def destroy
    asset = policy_scope(MediaAsset).find(params[:id])
    authorize asset
    listing = asset.listing
    filename = asset.filename
    DeliveryStorage.delete(asset.storage_key) if asset.storage_key.present?
    asset.destroy!
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: listing, event_type: "media_asset.deleted", payload: { filename: filename }) if listing
    head :no_content
  end

  private

  def create_params
    params.require(:media_asset).permit(
      :listing_id, :kind, :status, :storage_key, :source_url, :filename, :content_type, :byte_size,
      :width, :height, :duration_seconds, :category, :customer_visible, :order_id, :order_item_id, metadata: {}
    )
  end

  def update_params
    params.require(:media_asset).permit(:kind, :status, :filename, :content_type, :byte_size, :category, :customer_visible, :position, :cover, :hidden,
                                        :width, :height, :duration_seconds, :order_id, :order_item_id, metadata: {})
  end

  def serialize(asset)
    asset.slice(:id, :listing_id, :kind, :status, :storage_key, :source_url, :filename, :content_type,
                :byte_size, :width, :height, :duration_seconds, :category, :customer_visible,
                :position, :cover, :hidden, :metadata, :processed_at, :created_at, :order_id, :order_item_id).merge(
      cdn_url: asset.ready? ? (asset.source_url.presence || cdn_url_for(asset.storage_key)) : nil,
      download_path: asset.ready? && !asset.external? ? download_api_v1_media_asset_path(asset) : nil,
      uploaded_by: asset.uploaded_by && asset.uploaded_by.slice(:id, :name)
    )
  end

  def cdn_url_for(storage_key)
    cdn_base = ENV["MEDIA_CDN_URL"]
    return nil if cdn_base.blank?

    "#{cdn_base.chomp("/")}/#{URI::DEFAULT_PARSER.escape(storage_key)}"
  end

  def requested_category(uploaded_file)
    requested = params[:category].to_s
    return requested if MediaAsset::CATEGORIES.include?(requested)

    content_type = uploaded_file.content_type.to_s
    return "images" if content_type.start_with?("image/")
    return "videos" if content_type.start_with?("video/")

    "files"
  end

  def link_params
    params.permit(:source_url, :filename, :content_type, :category, :customer_visible, :order_id, :order_item_id, metadata: {})
  end

  def source_records
    order = params[:order_id].present? ? Current.organization.orders.find(params[:order_id]) : nil
    order_item = if params[:order_item_id].present?
      scope = OrderItem.joins(:order).where(orders: { organization_id: Current.organization.id })
      scope = scope.where(order_id: order.id) if order
      scope.find(params[:order_item_id])
    end
    { order: order || order_item&.order, order_item: order_item }
  end

  def record_listing_activity(asset, event_type, payload = {})
    return unless asset.listing

    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: asset.listing, event_type: event_type, payload: payload.presence || {})
  end

  def media_payload(asset)
    {
      media_asset_id: asset.id,
      filename: asset.filename,
      category: asset.category,
      content_type: asset.content_type,
      order_id: asset.order_id,
      order_item_id: asset.order_item_id
    }.compact
  end
end
