class MediaReviewAsset < ApplicationRecord
  belongs_to :media_review
  belongs_to :media_asset
  belongs_to :order_deliverable, optional: true
  has_many :media_review_threads, dependent: :nullify

  validates :filename, :content_type, presence: true
  validates :asset_version, :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :media_asset_id, uniqueness: { scope: :media_review_id }
  validate :asset_matches_review_snapshot

  private

  def asset_matches_review_snapshot
    return if media_review.blank? || media_asset.blank?

    errors.add(:media_asset, "must belong to the review organization") if media_asset.organization_id != media_review.organization_id
    errors.add(:media_asset, "must belong to the review listing") if media_asset.listing_id != media_review.listing_id
    unless media_asset.final? && media_asset.ready? && media_asset.customer_visible? && !media_asset.hidden?
      errors.add(:media_asset, "must be ready and customer-visible")
    end
    if order_deliverable.present? && media_asset.order_deliverable_id != order_deliverable.id
      errors.add(:order_deliverable, "must match the asset deliverable")
    end
  end
end
