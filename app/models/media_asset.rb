class MediaAsset < ApplicationRecord
  belongs_to :organization
  belongs_to :listing, optional: true
  belongs_to :uploaded_by, class_name: "User", optional: true
  belongs_to :order, optional: true
  belongs_to :order_item, optional: true
  belongs_to :media_group, optional: true

  enum :kind, { final: "final", raw: "raw", marketing: "marketing" }, validate: true
  enum :status, { pending: "pending", processing: "processing", ready: "ready", failed: "failed" }, validate: true

  CATEGORIES = %w[images videos floor_plans tours files].freeze

  validates :filename, :content_type, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :position, numericality: { greater_than_or_equal_to: 0 }
  validates :source_url, format: { with: %r{\Ahttps?://\S+\z}, allow_blank: true }

  def external?
    source_url.present?
  end

  # Only the upload endpoint derived a category from the file; assets registered
  # or linked without one fell to the column default and landed in "files",
  # which is how a listing ends up with 51 JPEGs that the images section cannot
  # see. An image filed under "files" is a mistake far more often than intent.
  before_validation :derive_category_from_content_type, on: :create

  validate :storage_source_present
  validate :related_records_belong_to_organization

  private

  def derive_category_from_content_type
    return unless category.blank? || category == "files"

    self.category = if content_type.to_s.start_with?("image/")
                      "images"
    elsif content_type.to_s.start_with?("video/")
                      "videos"
    else
                      category.presence || "files"
    end
  end

  def storage_source_present
    errors.add(:base, "a storage key or source URL is required") if storage_key.blank? && source_url.blank?
  end

  def related_records_belong_to_organization
    errors.add(:order, "must belong to the same organization") if order.present? && order.organization_id != organization_id
    errors.add(:order_item, "must belong to the selected order") if order_item.present? && order_item.order_id != order_id
    errors.add(:order_item, "must belong to the same organization") if order_item.present? && order_item.order.organization_id != organization_id
    errors.add(:listing, "must match the order listing") if order.present? && order.listing_id.present? && listing_id.present? && order.listing_id != listing_id
  end
end
