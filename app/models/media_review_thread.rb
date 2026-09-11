class MediaReviewThread < ApplicationRecord
  STATUSES = %w[open resolved outdated].freeze
  ANCHOR_TYPES = %w[asset region timestamp page].freeze

  belongs_to :media_review
  belongs_to :media_review_asset, optional: true
  belongs_to :order_deliverable, optional: true
  belongs_to :created_by, class_name: "User"
  belongs_to :resolved_by, class_name: "User", optional: true
  has_many :media_review_comments, dependent: :destroy

  enum :status, STATUSES.index_by(&:itself), validate: true
  enum :anchor_type, ANCHOR_TYPES.index_by(&:itself), validate: true

  validates :time_start_ms, :time_end_ms, :page_number, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :thread_context_matches_review
  validate :anchor_values_are_consistent

  private

  def thread_context_matches_review
    return if media_review.blank?

    if media_review_asset.present? && media_review_asset.media_review_id != media_review_id
      errors.add(:media_review_asset, "must belong to the review")
    end
    if order_deliverable.present? && !media_review.order_deliverable_ids.include?(order_deliverable_id)
      errors.add(:order_deliverable, "must belong to the review")
    end
    errors.add(:created_by, "must belong to the review organization") if created_by.present? && created_by.organization_id != media_review.organization_id
  end

  def anchor_values_are_consistent
    if timestamp? && time_start_ms.blank?
      errors.add(:time_start_ms, "is required for a timestamp comment")
    end
    if page? && page_number.blank?
      errors.add(:page_number, "is required for a page comment")
    end
    if region? && [ anchor_x, anchor_y, anchor_width, anchor_height ].any?(&:blank?)
      errors.add(:base, "region comments require x, y, width, and height")
    end
  end
end
