module MediaReviews
  # The listing's review page, shaped once for the customer and for staff.
  #
  # It is modelled on a merge request: the delivered files carry their
  # discussion threads inline, and each round of review sits on one timeline,
  # so both sides answer each other in the same place rather than in chat.
  # Threads span every round for the listing, so a question asked in review #1
  # is still on the file when review #2 is open.
  class Workspace
    # Files published without an order behind them (imported listings) are
    # grouped by kind, the way the portal media page shows them.
    def self.group_key(asset)
      category = asset&.category.to_s
      MediaAsset::CATEGORY_DEFINITIONS.key?(category) ? category : "files"
    end

    def self.group_order(category)
      MediaAsset::CATEGORIES.index(category) || MediaAsset::CATEGORIES.length
    end

    def self.group_definition(category)
      MediaAsset::CATEGORY_DEFINITIONS.fetch(category).slice(:title, :description, :deliverable_type)
    end

    def self.serialize_asset(asset, visible: true)
      ready = visible && asset.ready?
      asset.slice(:id, :filename, :content_type, :category, :version, :byte_size, :width, :height,
                  :duration_seconds).merge(
        cdn_url: ready ? DeliveryStorage.public_url(asset.storage_key) : nil,
        preview_path: ready ? "/api/v1/media_assets/#{asset.id}/preview" : nil,
        download_path: ready ? "/api/v1/media_assets/#{asset.id}/download" : nil
      )
    end

    def initialize(listing:, user:, reviews:, deliverables:)
      @listing = listing
      @user = user
      @reviews = reviews.includes(:created_by, :submitted_by, media_review_deliverables: :order_deliverable,
                                  media_review_threads: [ :resolved_by, :media_review_asset, { media_review_comments: :author } ])
                        .ordered.to_a
      @deliverables = deliverables.to_a
    end

    def as_json(*)
      threads = serialized_threads
      {
        listing: { id: listing.id, address: listing.address },
        review_state: current_review&.status || "implicitly_accepted",
        current_review: current_review && serialize_review(current_review),
        draft: draft && serialize_review(draft),
        can_start_review: customer? && (deliverables.any?(&:delivered?) || unassigned_assets.any?),
        pending_comment_count: threads.select { |thread| thread[:media_review_id] == draft&.id }
                                      .sum { |thread| thread[:comments].count { |comment| comment["status"] == "draft" } },
        unresolved_thread_count: threads.count { |thread| thread["status"] == "open" && !thread[:pending] },
        reviews: visible_reviews.map { |review| serialize_review(review) },
        deliverables: deliverables.map { |deliverable| serialize_deliverable(deliverable) },
        asset_groups: unassigned_asset_groups,
        threads:
      }
    end

    private

    attr_reader :listing, :user, :reviews, :deliverables

    def customer?
      !user.internal? && customer_account_ids.include?(listing.client_account_id)
    end

    def member?(review)
      !user.internal? && customer_account_ids.include?(review.client_account_id)
    end

    def customer_account_ids
      @customer_account_ids ||= user.client_account_ids
    end

    # Staff never see a draft, or a draft retired by a new delivery: until a
    # review is submitted it belongs to the customer.
    def visible_reviews
      @visible_reviews ||= reviews.select { |review| member?(review) || !(review.open? || review.outdated?) }
    end

    def current_review
      return @current_review if defined?(@current_review)

      current_version = deliverables.map(&:delivery_version).max.to_i
      @current_review = visible_reviews.find { |review| !review.outdated? && review.delivery_version == current_version }
    end

    def draft
      return @draft if defined?(@draft)

      @draft = reviews.find { |review| review.open? && member?(review) && !review.stale? }
    end

    def serialize_review(review)
      policy = MediaReviewPolicy.new(user, review)
      review.slice(:id, :number, :delivery_version, :status, :outcome, :summary, :summary_html, :created_at,
                   :submitted_at).merge(
        created_by: review.created_by.slice(:id, :name),
        submitted_by: review.submitted_by&.slice(:id, :name),
        can_submit: review.open? && policy.submit?
      )
    end

    def serialize_deliverable(deliverable)
      deliverable.slice(:id, :title, :description, :deliverable_type, :status, :target_on, :delivered_at,
                        :delivery_version).merge(
        # Only delivered work is snapshotted into a review, so only it takes comments.
        reviewable: deliverable.delivered?,
        assets: deliverable_assets.fetch(deliverable.id).map { |asset| self.class.serialize_asset(asset) }
      )
    end

    def serialized_threads
      reviews.flat_map do |review|
        review.media_review_threads.filter_map { |thread| serialize_thread(review, thread) }
      end.sort_by { |thread| [ thread["created_at"], thread["id"] ] }
    end

    def serialize_thread(review, thread)
      comments = visible_comments(review, thread)
      # A thread whose every comment is someone else's draft does not exist yet
      # for this viewer.
      return if comments.empty?

      snapshot = thread.media_review_asset
      original_id = snapshot&.media_asset_id
      current_id = original_id && current_asset_id(original_id)
      thread.slice(:id, :status, :anchor_type, :page_number, :time_start_ms, :time_end_ms, :resolved_at,
                   :created_at).merge(
        anchor_x: thread.anchor_x&.to_f,
        anchor_y: thread.anchor_y&.to_f,
        anchor_width: thread.anchor_width&.to_f,
        anchor_height: thread.anchor_height&.to_f,
        media_review_id: review.id,
        review_number: review.number,
        order_deliverable_id: thread.order_deliverable_id || snapshot&.order_deliverable_id,
        media_asset_id: current_id,
        original_media_asset_id: original_id,
        filename: snapshot&.filename,
        # Like a diff note after a new push: the thread stays with the file,
        # marked as written against an earlier version of it.
        outdated: thread.outdated? || (original_id.present? && current_id != original_id),
        file_available: current_id.present? && displayed_asset_ids.include?(current_id),
        pending: comments.all?(&:draft?),
        resolved_by: thread.resolved_by&.slice(:id, :name),
        capabilities: MediaReviewThreadPolicy.new(user, thread).capabilities,
        comments: comments.map { |comment| serialize_comment(comment) }
      )
    end

    def visible_comments(review, thread)
      drafts_visible = member?(review) && (review.open? || review.outdated?)
      thread.media_review_comments.select { |comment| comment.published? || (drafts_visible && comment.draft?) }
            .sort_by { |comment| [ comment.created_at, comment.id ] }
    end

    def serialize_comment(comment)
      comment.slice(:id, :body, :body_html, :status, :edited_at, :created_at).merge(
        author: { id: comment.author.id, name: comment.author.name, side: comment.author.internal? ? "staff" : "customer" },
        capabilities: MediaReviewCommentPolicy.new(user, comment).capabilities
      )
    end

    def current_asset_id(asset_id)
      seen = Set.new
      asset_id = superseded_by[asset_id] while superseded_by.key?(asset_id) && seen.add?(asset_id)
      asset_id
    end

    def superseded_by
      @superseded_by ||= listing.media_assets.where.not(superseded_by_id: nil).pluck(:id, :superseded_by_id).to_h
    end

    def deliverable_assets
      @deliverable_assets ||= begin
        assets = if deliverables.empty?
          []
        else
          MediaAsset.where(listing_id: listing.id, order_deliverable_id: deliverables.map(&:id))
            .current_version.final.ready.where(customer_visible: true, hidden: false)
            .order(:position, :created_at, :id).to_a
        end
        assets_by_deliverable = assets.group_by(&:order_deliverable_id)
        deliverables.to_h { |deliverable| [ deliverable.id, assets_by_deliverable.fetch(deliverable.id, []) ] }
      end
    end

    def unassigned_assets
      @unassigned_assets ||= listing.media_assets.current_version.final.ready
        .where(customer_visible: true, hidden: false, order_deliverable_id: nil)
        .order(:position, :created_at, :id).to_a
    end

    def unassigned_asset_groups
      unassigned_assets.group_by { |asset| self.class.group_key(asset) }
        .sort_by { |category, _| self.class.group_order(category) }
        .map do |category, assets|
          self.class.group_definition(category).merge(
            key: category,
            assets: assets.map { |asset| self.class.serialize_asset(asset) }
          )
        end
    end

    def displayed_asset_ids
      @displayed_asset_ids ||= (deliverable_assets.values.flatten + unassigned_assets).to_set(&:id)
    end
  end
end
