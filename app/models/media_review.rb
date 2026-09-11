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

  def submit!(outcome:, submitted_by:, summary: nil, summary_html: nil)
    outcome = outcome.to_s
    raise ArgumentError, "unsupported review outcome" unless OUTCOMES.include?(outcome)
    raise ActiveRecord::RecordInvalid, self unless open?

    transaction do
      sanitized_summary_html = RichTextSanitizer.sanitize(summary_html.to_s).presence
      update!(
        outcome:,
        status: outcome == "approve" ? :approved : outcome == "request_changes" ? :changes_requested : :submitted,
        submitted_by:,
        submitted_at: Time.current,
        summary: summary.presence || RichTextSanitizer.plain_text(sanitized_summary_html).presence,
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
