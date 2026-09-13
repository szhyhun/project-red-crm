class Api::V1::MediaReviewsController < Api::V1::BaseController
  # The listing's review page for either side: current files, every review
  # round, and every thread the viewer may see.
  def listing_index
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :view?

    render json: { workspace: workspace_payload(listing) }
  end

  def create
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :view?
    client_account = listing.client_account
    deliverables = selected_deliverables(listing)
    assets = reviewable_assets(listing, deliverables)
    if deliverables.empty? && assets.empty?
      return render json: { error: "no_delivered_media_to_review" }, status: :unprocessable_entity
    end

    review = open_draft_for(listing, client_account)
    status = review.present? ? :ok : :created
    review ||= Current.organization.media_reviews.build(
      listing:,
      client_account:,
      created_by: current_user,
      number: Current.organization.media_reviews.where(listing:, client_account:).maximum(:number).to_i + 1,
      delivery_version: (deliverables.map(&:delivery_version) + assets.map(&:version)).max.to_i
    )
    authorize review, review.new_record? ? :create? : :update?

    MediaReview.transaction do
      if review.new_record?
        review.save!
        ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: review,
                              event_type: "media_review.created", payload: { listing_id: listing.id })
      end
      review.include_media!(deliverables:, assets:)
    end

    render json: { media_review: serialize_review(review.reload) }, status:
  rescue ActiveRecord::RecordNotUnique
    # Another tab or a double click opened the draft first; resume that one.
    review = MediaReview.open_for(listing:, client_account:)
    raise if review.blank?

    render json: { media_review: serialize_review(review) }, status: :ok
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
    review_asset = resolve_review_asset(review, attributes)
    if (attributes[:media_review_asset_id].present? || attributes[:media_asset_id].present?) && review_asset.blank?
      return render json: { error: "invalid_review_asset_reference" }, status: :unprocessable_entity
    end

    deliverable = resolve_review_deliverable(review, attributes[:order_deliverable_id])
    thread = review.media_review_threads.build(
      media_review_asset: review_asset,
      order_deliverable: deliverable || review_asset&.order_deliverable,
      created_by: current_user,
      anchor_type: attributes[:anchor_type].presence || (review_asset.present? ? :asset : :deliverable),
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

  # A reply joins the draft while the review is open and is published at once
  # after submission, the way a reply to a merge request thread is.
  def create_comment
    thread = visible_thread
    authorize thread, :update?
    comment = thread.media_review_comments.build(
      comment_attributes.merge(author: current_user, status: thread.media_review.open? ? :draft : :published)
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
    thread = comment.media_review_thread
    MediaReview.transaction do
      comment.destroy!
      # A thread is its comments; removing the only one must not leave an empty
      # anchor behind for staff to find after submission.
      thread.destroy! unless thread.media_review_comments.exists?
    end
    head :no_content
  end

  def submit
    review = find_review
    authorize review, :submit?
    attributes = submit_params
    outcome = attributes[:outcome].to_s
    return render json: { error: "invalid_review_outcome" }, status: :unprocessable_entity unless MediaReview::OUTCOMES.include?(outcome)

    result = MediaReviews::Submit.call(
      review:, outcome:, submitted_by: current_user,
      summary: attributes[:summary], summary_html: attributes[:summary_html]
    )
    raise result.failure.original_error || result.failure if result.failure?

    render json: { media_review: serialize_review(result.fetch(:review)) }
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
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: thread.media_review,
                          event_type: "media_review.thread_reopened", payload: { thread_id: thread.id })
    render json: { media_review: serialize_review(thread.media_review.reload) }
  end

  private

  def workspace_payload(listing)
    MediaReviews::Workspace.new(
      listing:,
      user: current_user,
      reviews: policy_scope(MediaReview).where(listing:, client_account_id: listing.client_account_id),
      # Every active service is listed, as on the media page this replaces for
      # the customer: one still in production shows as such, and one sent back
      # keeps its threads beside its files.
      deliverables: policy_scope(OrderDeliverable).where(listing:).active.ordered
    ).as_json
  end

  # A draft is retired once an included service is delivered again, and the
  # customer starts over on the new files rather than resuming comments that
  # were written about the old ones.
  def open_draft_for(listing, client_account)
    review = policy_scope(MediaReview).where(listing:, client_account:).open.ordered.first
    return review unless review&.stale?

    review.mark_outdated!
    nil
  end

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

  # Customer review follows published media, not the internal order workflow.
  # An imported or manually uploaded file can be customer-visible without an
  # OrderDeliverable, and it must still be reviewable.
  def reviewable_assets(listing, deliverables)
    assets = listing.media_assets.current_version.final.ready
      .where(customer_visible: true, hidden: false)
      .order(:position, :created_at, :id)
    assets.where(order_deliverable_id: nil).or(assets.where(order_deliverable_id: deliverables.map(&:id))).to_a
  end

  def resolve_review_asset(review, attributes)
    if attributes[:media_review_asset_id].present?
      review.media_review_assets.find_by(id: attributes[:media_review_asset_id])
    elsif attributes[:media_asset_id].present?
      review.media_review_assets.find_by(media_asset_id: attributes[:media_asset_id])
    end
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
      :media_review_asset_id, :media_asset_id, :order_deliverable_id, :anchor_type, :page_number,
      :time_start_ms, :time_end_ms, :anchor_x, :anchor_y, :anchor_width, :anchor_height
    )
  end

  def comment_attributes
    params.require(:comment).permit(:body, :body_html)
  end

  def submit_params
    params.fetch(:media_review, {}).permit(:outcome, :summary, :summary_html)
  end

  def serialize_review(review)
    review = review_for_serialization(review)
    deliverable_assets = review.media_review_assets.group_by(&:order_deliverable_id)
    comments = visible_review_comments(review)
    comments_by_thread = comments.group_by(&:media_review_thread_id)
    review.slice(:id, :listing_id, :client_account_id, :number, :delivery_version, :status, :outcome,
                 :summary, :summary_html, :created_at, :submitted_at).merge(
      listing: { id: review.listing.id, address: review.listing.address },
      can_submit: review.open? && MediaReviewPolicy.new(current_user, review).submit?,
      pending_comment_count: comments.count(&:draft?),
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
      threads: review.media_review_threads.sort_by { |thread| [ thread.created_at, thread.id ] }
        .filter_map { |thread| serialize_thread(thread, comments_by_thread) }
    )
  end

  def review_for_serialization(review)
    required = %i[listing media_review_deliverables media_review_assets media_review_threads]
    return review if required.all? { |association| review.association(association).loaded? }

    Current.organization.media_reviews.includes(
      :listing, :client_account, :created_by, :submitted_by,
      media_review_deliverables: :order_deliverable,
      media_review_assets: [ :media_asset, :order_deliverable ],
      media_review_threads: [ :media_review_asset, { media_review_comments: :author } ]
    ).find(review.id)
  end

  def serialize_review_asset_groups(review)
    review.media_review_assets.select { |review_asset| review_asset.order_deliverable_id.nil? }
      .group_by { |review_asset| MediaReviews::Workspace.group_key(review_asset.media_asset) }
      .sort_by { |category, _| MediaReviews::Workspace.group_order(category) }
      .map do |category, assets|
        MediaReviews::Workspace.group_definition(category).merge(
          key: category,
          status: "delivered",
          asset_count: assets.length,
          assets: assets.sort_by { |asset| [ asset.position, asset.id ] }.map { |asset| serialize_review_asset(asset) }
        )
      end
  end

  def serialize_review_asset(review_asset)
    asset = review_asset.media_asset
    visible = MediaAssetPolicy.new(current_user, asset).view?
    review_asset.slice(:id, :media_asset_id, :order_deliverable_id, :asset_version, :filename, :content_type,
                       :byte_size, :position).merge(
      MediaReviews::Workspace.serialize_asset(asset, visible:)
        .slice(:category, :width, :height, :duration_seconds, :cdn_url, :preview_path, :download_path)
    )
  end

  def serialize_thread(thread, comments_by_thread)
    comments = comments_by_thread.fetch(thread.id, [])
    # Staff must not see a thread that is still only the customer's draft.
    return if comments.empty?

    thread.slice(:id, :media_review_asset_id, :order_deliverable_id, :status, :anchor_type, :page_number,
                 :time_start_ms, :time_end_ms, :anchor_x, :anchor_y, :anchor_width, :anchor_height,
                 :resolved_at, :created_at).merge(
      comments: comments.sort_by { |comment| [ comment.created_at, comment.id ] }.map do |comment|
        comment.slice(:id, :body, :body_html, :status, :edited_at, :created_at).merge(
          author: comment.author.slice(:id, :name, :role)
        )
      end
    )
  end

  def visible_review_comments(review)
    comments = review.media_review_threads.flat_map(&:media_review_comments)
    visible = comments.select(&:published?)
    if !current_user.internal? && current_user.client_account_ids.include?(review.client_account_id) && review.open?
      visible.concat(comments.select(&:draft?))
    end
    visible
  end
end
