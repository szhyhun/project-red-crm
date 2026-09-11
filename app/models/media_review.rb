class MediaReview < ApplicationRecord
  STATUSES = %w[open submitted changes_requested approved outdated].freeze
  OUTCOMES = %w[comment request_changes approve].freeze

  belongs_to :organization
  belongs_to :listing
  belongs_to :client_account
  belongs_to :created_by, class_name: "User"
  belongs_to :submitted_by, class_name: "User", optional: true
  has_many :media_review_deliverables, dependent: :destroy
  has_many :order_deliverables, through: :media_review_deliverables
  has_many :media_review_assets, dependent: :destroy
  has_many :media_assets, through: :media_review_assets
  has_many :media_review_threads, dependent: :destroy
  has_many :media_review_comments, through: :media_review_threads
  has_many :messages, dependent: :nullify
  has_many :activity_events, as: :subject, dependent: :destroy

  enum :status, STATUSES.index_by(&:itself), validate: true
  enum :outcome, OUTCOMES.index_by(&:itself), validate: { allow_nil: true }

  validates :number, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :delivery_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :number, uniqueness: { scope: %i[listing_id client_account_id] }
  validate :records_belong_to_same_organization
  validate :listing_belongs_to_client_account

  scope :ordered, -> { order(number: :desc, created_at: :desc, id: :desc) }
  scope :for_delivery_version, ->(version) { where(delivery_version: version) }

  def self.open_for(listing:, client_account:)
    where(listing:, client_account:).open.ordered.first
  end

  # A draft is written against one delivery. Once an included service is
  # delivered again its files may have been replaced, and resuming the draft
  # would put old comments on new work.
  def stale?
    media_review_deliverables.includes(:order_deliverable).any? do |join|
      join.order_deliverable.delivery_version != join.delivery_version
    end
  end

  def mark_outdated!
    transaction do
      update!(status: :outdated)
      media_review_threads.update_all(status: "outdated", updated_at: Time.current)
    end
  end

  # Brings a draft up to date with what is published now, so a service
  # delivered after the draft was opened, or a file added since, can still be
  # commented on. Existing snapshot rows are never rewritten: they record what
  # the customer was shown.
  def include_media!(deliverables:, assets:)
    deliverables.each_with_index do |deliverable, position|
      media_review_deliverables.find_or_create_by!(order_deliverable: deliverable) do |join|
        join.delivery_version = deliverable.delivery_version
        join.position = position
      end
    end
    deliverables_by_id = deliverables.index_by(&:id)
    assets.each_with_index do |asset, position|
      media_review_assets.find_or_create_by!(media_asset: asset) do |snapshot|
        snapshot.assign_attributes(order_deliverable: deliverables_by_id[asset.order_deliverable_id],
                                   asset_version: asset.version.to_i, filename: asset.filename,
                                   content_type: asset.content_type, byte_size: asset.byte_size, position:)
      end
    end
  end

  def submit!(outcome:, submitted_by:, summary: nil, summary_html: nil)
    outcome = outcome.to_s
    raise ArgumentError, "unsupported review outcome" unless OUTCOMES.include?(outcome)

    # The row lock makes a double click or a second tab wait for the first
    # submit and then find the review closed, instead of moving the same work
    # back twice and posting two notifications.
    with_lock do
      reject!("This review has already been submitted") unless open?

      sanitized_summary_html = RichTextSanitizer.sanitize(summary_html.to_s).presence
      summary_text = summary.presence || RichTextSanitizer.plain_text(sanitized_summary_html).presence
      # Sending work back to production with nothing to act on leaves the
      # team guessing what to change.
      if outcome == "request_changes" && summary_text.blank? && media_review_comments.none?
        reject!("Add a comment or a summary that says what should change")
      end

      update!(
        outcome:,
        status: outcome == "approve" ? :approved : outcome == "request_changes" ? :changes_requested : :submitted,
        submitted_by:,
        submitted_at: Time.current,
        summary: summary_text,
        summary_html: sanitized_summary_html
      )
      media_review_comments.where(status: :draft).update_all(status: "published", updated_at: Time.current)

      if request_changes?
        order_deliverables.each do |deliverable|
          next unless deliverable.delivered?

          deliverable.update!(status: :in_progress, delivered_at: nil)
        end
      end

      ActivityEvent.create!(
        organization: organization,
        actor: submitted_by,
        subject: self,
        event_type: "media_review.#{outcome}",
        payload: { listing_id: listing_id, order_deliverable_ids: order_deliverables.ids }
      )
      if request_changes?
        order_deliverables.each do |deliverable|
          ActivityEvent.create!(
            organization: organization,
            actor: submitted_by,
            subject: deliverable,
            event_type: "order_deliverable.change_requested",
            payload: { media_review_id: id }
          )
        end
      end
    end

    self
  end

  private

  def reject!(message)
    errors.add(:base, message)
    raise ActiveRecord::RecordInvalid, self
  end

  def records_belong_to_same_organization
    errors.add(:listing, "must belong to the same organization") if listing.present? && listing.organization_id != organization_id
    errors.add(:client_account, "must belong to the same organization") if client_account.present? && client_account.organization_id != organization_id
    errors.add(:created_by, "must belong to the same organization") if created_by.present? && created_by.organization_id != organization_id
    if submitted_by.present? && submitted_by.organization_id != organization_id
      errors.add(:submitted_by, "must belong to the same organization")
    end
  end

  def listing_belongs_to_client_account
    return if listing.blank? || client_account.blank?
    return if listing.client_account_id == client_account_id || listing.listing_customers.exists?(client_account_id: client_account_id)

    errors.add(:client_account, "must have access to the listing")
  end
end
