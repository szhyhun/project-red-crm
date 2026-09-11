class Api::V1::MediaReviewsController < Api::V1::BaseController
  def listing_index
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :view?
    reviews = policy_scope(MediaReview).where(listing: listing).ordered
    current_review = reviews.first

    render json: {
      reviews: reviews.map { |review| serialize_summary(review) },
      current_review: current_review && serialize_summary(current_review),
      review_state: current_review&.status || "implicitly_accepted"
    }
  end

  def create
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :view?
    client_account = listing.client_account
    review = policy_scope(MediaReview).where(listing:, client_account:).open.ordered.first
    return render json: { media_review: serialize_review(review) }, status: :ok if review.present?

    deliverables = selected_deliverables(listing)
    reviewable_assets = reviewable_assets(listing, deliverables)
    if reviewable_assets.empty?
      return render json: { error: "no_delivered_media_to_review" }, status: :unprocessable_entity
    end
    # Customer review follows published media, not the internal order workflow.
    # An imported or manually uploaded file can be customer-visible without an
    # OrderDeliverable, and it must still be reviewable.
    current_version = (deliverables.map(&:delivery_version) + reviewable_assets.map(&:version)).max.to_i
    existing_review = policy_scope(MediaReview)
      .where(listing:, client_account:, delivery_version: current_version)
      .where.not(status: :outdated)
      .ordered.first
    return render json: { media_review: serialize_review(existing_review) }, status: :ok if existing_review.present?

    review = Current.organization.media_reviews.build(
      listing:,
      client_account:,
      created_by: current_user,
      number: Current.organization.media_reviews.where(listing:, client_account:).maximum(:number).to_i + 1,
      delivery_version: current_version
    )
    authorize review, :create?

    MediaReview.transaction do
      review.save!
      deliverables.each_with_index do |deliverable, deliverable_position|
        review.media_review_deliverables.create!(
          order_deliverable: deliverable,
          delivery_version: deliverable.delivery_version,
          position: deliverable_position
        )
      end
      reviewable_assets.each_with_index do |asset, asset_position|
        deliverable = deliverables.find { |candidate| candidate.id == asset.order_deliverable_id }
        review.media_review_assets.create!(
          media_asset: asset,
          order_deliverable: deliverable,
          asset_version: asset.version.to_i,
          filename: asset.filename,
          content_type: asset.content_type,
          byte_size: asset.byte_size,
          position: asset_position
        )
      end
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: review,
                            event_type: "media_review.created", payload: { listing_id: listing.id })
    end

    render json: { media_review: serialize_review(review.reload) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def show
    review = find_review
    authorize review, :view?
    render json: { media_review: serialize_review(review) }
  end

  def create_thread
    review = find_review
    authorize review, :update?
    attributes = thread_params
    review_asset = review.media_review_assets.find_by(id: attributes[:media_review_asset_id])
    if attributes[:media_review_asset_id].present? && review_asset.blank?
      return render json: { error: "invalid_review_asset_reference" }, status: :unprocessable_entity
    end

    thread = review.media_review_threads.build(
      media_review_asset: review_asset,
      order_deliverable: resolve_review_deliverable(review, attributes[:order_deliverable_id]),
      created_by: current_user,
      anchor_type: attributes[:anchor_type].presence || (review_asset.present? ? :asset : :page),
      page_number: attributes[:page_number],
      time_start_ms: attributes[:time_start_ms],
      time_end_ms: attributes[:time_end_ms],
      anchor_x: attributes[:anchor_x],
      anchor_y: attributes[:anchor_y],
      anchor_width: attributes[:anchor_width],
      anchor_height: attributes[:anchor_height]
    )
    authorize thread, :create?
    comment = thread.media_review_comments.build(comment_attributes.merge(author: current_user, status: :draft))

    MediaReview.transaction do
      thread.save!
      comment.save!
    end

    render json: { media_review: serialize_review(review.reload) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def create_comment
    thread = visible_thread
    authorize thread, :create?
    comment = thread.media_review_comments.build(
      comment_attributes.merge(author: current_user, status: current_user.internal? ? :published : :draft)
    )
    authorize comment, :create?

    if comment.save
      ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: thread.media_review,
                            event_type: "media_review.comment_added", payload: { thread_id: thread.id, comment_id: comment.id })
      render json: { media_review: serialize_review(thread.media_review.reload) }, status: :created
    else
      render_validation_errors(comment)
    end
  end

  def update_comment
    comment = visible_comment
    authorize comment, :update?
    if comment.update(comment_attributes.merge(edited_at: Time.current))
      render json: { media_review: serialize_review(comment.media_review_thread.media_review.reload) }
    else
      render_validation_errors(comment)
    end
  end

  def destroy_comment
    comment = visible_comment
    authorize comment, :destroy?
    comment.destroy!
    head :no_content
  end

  def submit
    review = find_review
    authorize review, :submit?
    attributes = submit_params
    outcome = attributes[:outcome].to_s
    return render json: { error: "invalid_review_outcome" }, status: :unprocessable_entity unless MediaReview::OUTCOMES.include?(outcome)

    review.submit!(outcome:, submitted_by: current_user, summary: attributes[:summary], summary_html: attributes[:summary_html])
    notify_review_submission(review)
    render json: { media_review: serialize_review(review.reload) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def resolve_thread
    thread = visible_thread
    authorize thread, :manage?
    thread.update!(status: :resolved, resolved_by: current_user, resolved_at: Time.current)
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: thread.media_review,
                          event_type: "media_review.thread_resolved", payload: { thread_id: thread.id })
    render json: { media_review: serialize_review(thread.media_review.reload) }
  end

  def reopen_thread
    thread = visible_thread
    authorize thread, :manage?
    thread.update!(status: :open, resolved_by: nil, resolved_at: nil)
    render json: { media_review: serialize_review(thread.media_review.reload) }
  end

  private

  def find_review
    MediaReviewPolicy::Scope.new(current_user, MediaReview).resolve
      .includes(:listing, :client_account, :created_by, :submitted_by,
                media_review_deliverables: :order_deliverable,
                media_review_assets: [ :media_asset, :order_deliverable ],
                media_review_threads: { media_review_comments: :author })
      .find(params[:id])
  end

  def visible_thread
    MediaReviewThread.joins(:media_review)
      .merge(MediaReviewPolicy::Scope.new(current_user, MediaReview).resolve)
      .includes(:media_review, :media_review_asset, media_review_comments: :author)
      .find(params[:id])
  end

  def visible_comment
    MediaReviewComment.joins(media_review_thread: :media_review)
      .merge(MediaReviewPolicy::Scope.new(current_user, MediaReview).resolve)
      .includes(media_review_thread: :media_review)
      .find(params[:id])
  end

  def selected_deliverables(listing)
    relation = policy_scope(OrderDeliverable).where(listing: listing).active.where(status: :delivered)
    ids = Array(review_params[:order_deliverable_ids]).filter_map { |id| Integer(id, exception: false) }.uniq
    return relation.includes(:media_assets).ordered.to_a if ids.empty?
    return [] if ids.length != Array(review_params[:order_deliverable_ids]).length

    selected = relation.where(id: ids).includes(:media_assets).ordered.to_a
    selected.length == ids.length ? selected : []
  end

  def reviewable_assets(listing, deliverables)
    assets = listing.media_assets.current_version.final.ready
      .where(customer_visible: true, hidden: false)
      .order(:position, :created_at, :id)
    return assets.to_a if deliverables.empty?

    assets.where(order_deliverable_id: nil)
      .or(assets.where(order_deliverable_id: deliverables.map(&:id))).to_a
  end

  def resolve_review_deliverable(review, id)
    return if id.blank?

    review.order_deliverables.find(id)
  end

  def review_params
    params.fetch(:media_review, {}).permit(order_deliverable_ids: [])
  end

  def thread_params
    params.fetch(:thread, {}).permit(
      :media_review_asset_id, :order_deliverable_id, :anchor_type, :page_number,
      :time_start_ms, :time_end_ms, :anchor_x, :anchor_y, :anchor_width, :anchor_height
    )
  end

  def comment_attributes
    params.require(:comment).permit(:body, :body_html)
  end

  def submit_params
    params.fetch(:media_review, {}).permit(:outcome, :summary, :summary_html)
  end

  def serialize_summary(review)
    review.slice(:id, :number, :delivery_version, :status, :outcome, :created_at, :submitted_at).merge(
      pending_comment_count: review.open? && current_user.client_account_ids.include?(review.client_account_id) ? review.media_review_comments.where(status: :draft).count : 0,
      listing: { id: review.listing_id, address: review.listing.address }
    )
  end

  def serialize_review(review)
    deliverable_assets = review.media_review_assets.group_by(&:order_deliverable_id)
    review.slice(:id, :listing_id, :client_account_id, :number, :delivery_version, :status, :outcome,
                 :summary, :summary_html, :created_at, :submitted_at).merge(
      listing: { id: review.listing.id, address: review.listing.address },
      can_submit: review.open? && current_user.client_account_ids.include?(review.client_account_id) && !current_user.internal?,
      pending_comment_count: visible_review_comments(review).count(&:draft?),
      deliverables: review.media_review_deliverables.sort_by { |join| [ join.position, join.id ] }.map do |join|
        deliverable = join.order_deliverable
        deliverable.slice(:id, :title, :description, :deliverable_type, :status, :target_on, :delivered_at,
                          :scope_label).merge(
          delivery_version: join.delivery_version,
          asset_count: deliverable_assets.fetch(deliverable.id, []).length,
          assets: deliverable_assets.fetch(deliverable.id, []).sort_by { |asset| [ asset.position, asset.id ] }.map { |asset| serialize_review_asset(asset) }
        )
      end,
      asset_groups: serialize_review_asset_groups(review),
      threads: review.media_review_threads.sort_by { |thread| [ thread.created_at, thread.id ] }.map { |thread| serialize_thread(thread) }
    )
  end

  def serialize_review_asset_groups(review)
    grouped_assets = review.media_review_assets.select { |review_asset| review_asset.order_deliverable_id.nil? }
      .group_by do |review_asset|
        category = review_asset.media_asset&.category.to_s
        Api::V1::PortalController::PORTAL_ASSET_GROUPS.key?(category) ? category : "files"
      end

    grouped_assets.sort_by { |category, _| MediaAsset::CATEGORIES.index(category) || MediaAsset::CATEGORIES.length }
      .map do |category, assets|
        definition = Api::V1::PortalController::PORTAL_ASSET_GROUPS.fetch(category)
        {
          key: category,
          title: definition.fetch(:title),
          description: definition.fetch(:description),
          deliverable_type: definition.fetch(:deliverable_type),
          status: "delivered",
          asset_count: assets.length,
          assets: assets.sort_by { |asset| [ asset.position, asset.id ] }.map { |asset| serialize_review_asset(asset) }
        }
      end
  end

  def serialize_review_asset(review_asset)
    asset = review_asset.media_asset
    visible = asset.present? && MediaAssetPolicy.new(current_user, asset).view?
    review_asset.slice(:id, :media_asset_id, :order_deliverable_id, :asset_version, :filename, :content_type,
                       :byte_size, :position).merge(
      category: asset&.category,
      width: asset&.width,
      height: asset&.height,
      duration_seconds: asset&.duration_seconds,
      cdn_url: visible && asset.ready? ? asset.source_url.presence || DeliveryStorage.public_url(asset.storage_key) : nil,
      preview_path: visible && asset.ready? ? "/api/v1/media_assets/#{asset.id}/preview" : nil,
      download_path: visible && asset.ready? ? "/api/v1/media_assets/#{asset.id}/download" : nil
    )
  end

  def serialize_thread(thread)
    thread.slice(:id, :media_review_asset_id, :order_deliverable_id, :status, :anchor_type, :page_number,
                 :time_start_ms, :time_end_ms, :anchor_x, :anchor_y, :anchor_width, :anchor_height,
                 :resolved_at, :created_at).merge(
      comments: visible_review_comments(thread.media_review).select { |comment| comment.media_review_thread_id == thread.id }
        .sort_by { |comment| [ comment.created_at, comment.id ] }.map do |comment|
          comment.slice(:id, :body, :body_html, :status, :edited_at, :created_at).merge(
            author: comment.author.slice(:id, :name, :role)
          )
        end
    )
  end

  def visible_review_comments(review)
    comments = review.media_review_comments.includes(:author).to_a.select(&:published?)
    if !current_user.internal? && current_user.client_account_ids.include?(review.client_account_id) && review.open?
      comments.concat(review.media_review_comments.to_a.select(&:draft?))
    end
    comments.uniq
  end

  def notify_review_submission(review)
    conversation = Conversation.account_thread_for(
      organization: Current.organization,
      client_account: review.client_account,
      subject: "Media review ##{review.number}"
    )
    conversation.conversation_memberships.find_or_create_by!(user: current_user) { |membership| membership.role = :participant }
    review.client_account.users.active.find_each do |member|
      conversation.conversation_memberships.find_or_create_by!(user: member) { |membership| membership.role = :participant }
    end
    message = conversation.messages.create!(
      author: current_user,
      body: "Media review ##{review.number} was submitted: #{review.outcome.humanize}.",
      message_kind: :review_notification,
      listing: review.listing,
      media_review: review
    )
    conversation.update!(last_message_at: message.created_at)
    Conversations::NotifyJob.perform_later(message.id)
  rescue StandardError => error
    Rails.logger.error("Could not queue media review notification for review #{review.id}: #{error.class}: #{error.message}")
  end
end
