class Api::V1::MediaAssetsController < Api::V1::BaseController
  def index
    assets = policy_scope(MediaAsset).includes(:listing, :uploaded_by, :order, :order_item).order(:category, :position, :created_at)
    assets = assets.where(listing_id: params[:listing_id]) if params[:listing_id].present?
    authorize MediaAsset, :index?
    render json: { media_assets: assets.map { |asset| serialize(asset) } }
  end

  def create
    listing = policy_scope(Listing).find(create_params.fetch(:listing_id))
    records = source_records
    validate_listing_lineage!(listing, records[:order_deliverable])
    asset = Current.organization.media_assets.build(create_params.except(:order_id, :order_item_id, :order_deliverable_id).merge(
      listing: listing,
      uploaded_by: current_user,
      **records
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
    render json: { media_assets: assets.map { |asset| serialize(asset) }, media_asset: serialize(assets.first) }, status: :created
  rescue DeliveryStorage::MissingFile, DeliveryStorage::WriteError => error
    Rails.logger.warn("Media asset upload failed: #{error.class}: #{error.message}")
    render json: { error: "upload_failed" }, status: :unprocessable_entity
  end

  def link
    listing = policy_scope(Listing).find(params.require(:listing_id))
    authorize MediaAsset, :create?
    records = source_records
    validate_listing_lineage!(listing, records[:order_deliverable])
    asset = Current.organization.media_assets.build(link_params.merge(
      listing: listing,
      uploaded_by: current_user,
      kind: params.fetch(:kind, "final"),
      status: :ready,
      storage_key: nil,
      **records
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
    order_deliverable_id = params[:order_deliverable_id].presence
    asset_ids = Array(params.require(:asset_ids)).map(&:to_i)
    raise ActiveRecord::RecordNotFound unless asset_ids.present? && asset_ids == asset_ids.uniq
    scoped_assets = listing.media_assets.where(category: category)
    scoped_assets = if order_deliverable_id
      scoped_assets.where(order_deliverable_id:)
    else
      scoped_assets.where(order_deliverable_id: nil)
    end
    assets = scoped_assets.where(id: asset_ids).index_by(&:id)
    raise ActiveRecord::RecordNotFound unless assets.size == asset_ids.size

    MediaAsset.transaction do
      asset_ids.each_with_index { |asset_id, position| assets.fetch(asset_id).update!(position: position) }
    end
    render json: { media_assets: scoped_assets.order(:position, :created_at).map { |asset| serialize(asset) } }
  end

  def replace
    asset = policy_scope(MediaAsset).find(params[:id])
    authorize asset, :update?
    uploaded_file = params.require(:file)
    new_key = DeliveryStorage.key_for(organization: Current.organization, listing: asset.listing, filename: uploaded_file.original_filename)
    content_type = UploadContentType.for(uploaded_file)
    return render json: { error: "unsupported_content_type" }, status: :unprocessable_entity unless MediaAsset.safe_storage_content_type?(content_type)

    DeliveryStorage.write(upload: uploaded_file.tempfile, key: new_key, content_type: content_type)
    replacement = MediaAsset.transaction do
      replacement = Current.organization.media_assets.create!(
        listing: asset.listing,
        uploaded_by: current_user,
        order: asset.order,
        order_item: asset.order_item,
        order_deliverable: asset.order_deliverable,
        media_group: asset.media_group,
        kind: asset.kind,
        status: :pending,
        storage_key: new_key,
        source_url: nil,
        filename: uploaded_file.original_filename,
        content_type: content_type,
        byte_size: uploaded_file.size,
        width: asset.width,
        height: asset.height,
        duration_seconds: asset.duration_seconds,
        category: asset.category,
        customer_visible: asset.customer_visible,
        position: asset.position,
        cover: asset.cover,
        hidden: asset.hidden,
        version: asset.version.to_i + 1,
        metadata: asset.metadata.except("processing_error")
      )
      asset.update!(superseded_by: replacement)
      replacement
    end
    MediaAssets::VerifyUploadJob.perform_later(replacement.id)
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: replacement, event_type: "media_asset.replaced")
    record_listing_activity(replacement, "media_asset.replaced", media_payload(replacement))
    render json: { media_asset: serialize(replacement) }
  rescue DeliveryStorage::MissingFile, DeliveryStorage::WriteError => error
    DeliveryStorage.delete(new_key) if defined?(new_key) && new_key.present?
    Rails.logger.warn("Media asset replacement failed: #{error.class}: #{error.message}")
    render json: { error: "replace_failed" }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => error
    DeliveryStorage.delete(new_key) if defined?(new_key) && new_key.present?
    render_validation_errors(error.record)
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
    content_type = UploadContentType.for(uploaded_file)
    records = source_records
    validate_listing_lineage!(listing, records[:order_deliverable])
    deliverable_id = records[:order_deliverable]&.id
    asset = Current.organization.media_assets.build(
      listing: listing,
      uploaded_by: current_user,
      kind: params.fetch(:kind, "final"),
      category: category,
      position: listing.media_assets.where(category: category, order_deliverable_id: deliverable_id).maximum(:position).to_i + 1,
      customer_visible: ActiveModel::Type::Boolean.new.cast(params.fetch(:customer_visible, true)),
      status: :pending,
      storage_key: storage_key,
      filename: uploaded_file.original_filename,
      content_type: content_type,
      byte_size: uploaded_file.size,
      **records
    )

    unless MediaAsset.safe_storage_content_type?(content_type)
      asset.errors.add(:content_type, "is not supported for delivery media")
      raise ActiveRecord::RecordInvalid, asset
    end

    if asset.save
      DeliveryStorage.write(upload: uploaded_file.tempfile, key: storage_key, content_type: content_type)
      MediaAssets::VerifyUploadJob.perform_later(asset.id)
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: asset, event_type: "media_asset.uploaded")
      record_listing_activity(asset, "media_asset.uploaded", media_payload(asset))
      asset
    else
      raise ActiveRecord::RecordInvalid, asset
    end
  rescue DeliveryStorage::MissingFile, DeliveryStorage::WriteError => error
    DeliveryStorage.delete(storage_key) if storage_key.present?
    Rails.logger.warn("Media asset storage failed: #{error.class}: #{error.message}")
    asset&.update(status: :failed, metadata: asset.metadata.merge("processing_error" => "upload_failed"))
    raise
  end

  def download
    asset = policy_scope(MediaAsset).find(params[:id])
    # Taking the file away is its own permission: a team may lock downloads
    # until its listing is paid for, while the preview stays visible.
    authorize asset, :download?
    return redirect_to asset.source_url, allow_other_host: true if asset.external? && asset.ready?
    return render json: { error: "asset_not_ready" }, status: :unprocessable_entity unless asset.ready?
    return redirect_to DeliveryStorage.temporary_url(asset.storage_key), allow_other_host: true if DeliveryStorage.s3?

    send_file DeliveryStorage.path_for(asset.storage_key), type: "application/octet-stream", disposition: "attachment", filename: asset.filename
  rescue DeliveryStorage::MissingFile
    render json: { error: "asset_missing" }, status: :not_found
  end

  def preview
    asset = policy_scope(MediaAsset).find(params[:id])
    authorize asset, :show?
    return redirect_to asset.source_url, allow_other_host: true if asset.external? && asset.ready?
    return render json: { error: "asset_not_ready" }, status: :unprocessable_entity unless asset.ready?
    if DeliveryStorage.s3?
      if MediaAsset.safe_inline_content_type?(asset.content_type)
        return redirect_to DeliveryStorage.temporary_url(asset.storage_key, content_type: asset.content_type), allow_other_host: true
      end

      return redirect_to DeliveryStorage.temporary_url(asset.storage_key, content_type: "application/octet-stream", disposition: "attachment"), allow_other_host: true
    end

    disposition = MediaAsset.safe_inline_content_type?(asset.content_type) ? "inline" : "attachment"
    response_type = disposition == "inline" ? asset.content_type : "application/octet-stream"
    send_file DeliveryStorage.path_for(asset.storage_key),
              type: response_type,
              disposition: disposition,
              filename: asset.filename
  rescue DeliveryStorage::MissingFile
    render json: { error: "asset_missing" }, status: :not_found
  end

  def update
    asset = policy_scope(MediaAsset).find(params[:id])
    authorize asset

    if asset.update(resolve_update_relations(update_params))
      if asset.cover?
        asset.listing&.media_assets&.where(category: asset.category)&.where.not(id: asset.id)&.update_all(cover: false)
      end
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: asset, event_type: "media_asset.updated")
      record_listing_activity(asset, "media_asset.updated", media_payload(asset))
      render json: { media_asset: serialize(asset) }
    else
      render_validation_errors(asset)
    end
  end

  def destroy
    asset = policy_scope(MediaAsset).find(params[:id])
    authorize asset
    listing = asset.listing
    payload = media_payload(asset)
    DeliveryStorage.delete(asset.storage_key) if asset.storage_key.present?
    asset.destroy!
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: listing, event_type: "media_asset.deleted", payload: payload) if listing
    head :no_content
  end

  private

  def create_params
    params.require(:media_asset).permit(
      :listing_id, :kind, :status, :source_url, :filename, :content_type, :byte_size,
      :width, :height, :duration_seconds, :category, :customer_visible, :order_id, :order_item_id,
      :order_deliverable_id, metadata: {}
    )
  end

  def update_params
    params.require(:media_asset).permit(:kind, :status, :filename, :content_type, :byte_size, :category, :customer_visible, :position, :cover, :hidden,
                                        :width, :height, :duration_seconds, :order_id, :order_item_id,
                                        :order_deliverable_id, :media_group_id, metadata: {})
  end

  def serialize(asset)
    # Customer-visible deliverable files may be read directly from the public
    # CDN; private or non-ready files must remain behind the authorized API
    # route. Never substitute a private storage URL here: API redirects to S3
    # are not a browser-safe preview contract without matching bucket CORS.
    cdn_url = if asset.ready? && asset.customer_visible? && !asset.hidden?
      asset.order_deliverable.blank? ? (asset.source_url.presence || cdn_url_for(asset.storage_key)) : cdn_url_for(asset.storage_key)
    end

    asset.slice(:id, :listing_id, :kind, :status, :source_url, :filename, :content_type,
                :byte_size, :width, :height, :duration_seconds, :category, :customer_visible,
                :position, :cover, :hidden, :metadata, :processed_at, :created_at, :order_id, :order_item_id,
                :order_deliverable_id, :media_group_id, :version, :superseded_by_id).merge(
      cdn_url:,
      preview_path: asset.ready? && !asset.external? ? preview_api_v1_media_asset_path(asset) : nil,
      download_path: asset.ready? && !asset.external? ? download_api_v1_media_asset_path(asset) : nil,
      uploaded_by: asset.uploaded_by && asset.uploaded_by.slice(:id, :name)
    )
  end

  def cdn_url_for(storage_key)
    DeliveryStorage.public_url(storage_key)
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
    params.permit(:source_url, :filename, :content_type, :category, :customer_visible, :order_id, :order_item_id,
                  :order_deliverable_id, metadata: {})
  end

  def resolve_update_relations(attributes)
    attributes = attributes.to_h.symbolize_keys
    if attributes.key?(:order_deliverable_id)
      deliverable_id = attributes.delete(:order_deliverable_id)
      attributes[:order_deliverable] = Current.organization.order_deliverables.find(deliverable_id)
    end
    attributes
  end

  def validate_listing_lineage!(listing, deliverable)
    return if deliverable.blank? || deliverable.listing_id.blank? || deliverable.listing_id == listing.id

    raise ActiveRecord::RecordNotFound
  end

  def source_records
    order = params[:order_id].present? ? Current.organization.orders.find(params[:order_id]) : nil
    order_item = if params[:order_item_id].present?
      scope = OrderItem.joins(:order).where(orders: { organization_id: Current.organization.id })
      scope = scope.where(order_id: order.id) if order
      scope.find(params[:order_item_id])
    end
    deliverable = if params[:order_deliverable_id].present?
      Current.organization.order_deliverables.includes(:order, :listing, :order_item).find(params[:order_deliverable_id])
    end
    if deliverable.present?
      raise ActiveRecord::RecordNotFound if order.present? && deliverable.order_id != order.id
      raise ActiveRecord::RecordNotFound if order_item.present? && deliverable.order_item_id != order_item.id
    end
    { order: order || order_item&.order || deliverable&.order, order_item: order_item || deliverable&.order_item,
      order_deliverable: deliverable }
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
      order_item_id: asset.order_item_id,
      order_deliverable_id: asset.order_deliverable_id
    }.compact
  end
end
