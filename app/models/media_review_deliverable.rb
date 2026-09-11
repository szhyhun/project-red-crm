class MediaReviewDeliverable < ApplicationRecord
  belongs_to :media_review
  belongs_to :order_deliverable

  validates :delivery_version, :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :order_deliverable_id, uniqueness: { scope: :media_review_id }
  validate :records_match_review

  private

  def records_match_review
    return if media_review.blank? || order_deliverable.blank?

    errors.add(:order_deliverable, "must belong to the review listing") if order_deliverable.listing_id != media_review.listing_id
    errors.add(:order_deliverable, "must belong to the review organization") if order_deliverable.organization_id != media_review.organization_id
  end
end
