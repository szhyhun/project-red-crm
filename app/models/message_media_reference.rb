class MessageMediaReference < ApplicationRecord
  belongs_to :message
  belongs_to :media_asset

  validates :media_asset_id, uniqueness: { scope: :message_id }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :records_belong_to_same_organization
  validate :asset_matches_message_context

  private

  def records_belong_to_same_organization
    return if message.blank? || media_asset.blank?
    return if message.conversation.organization_id == media_asset.organization_id

    errors.add(:base, "message and media asset must belong to the same organization")
  end

  def asset_matches_message_context
    return if message.blank? || media_asset.blank?
    if message.order_deliverable_id.present? && media_asset.order_deliverable_id != message.order_deliverable_id
      errors.add(:media_asset, "must belong to the message deliverable")
    elsif message.listing_id.present? && media_asset.listing_id != message.listing_id
      errors.add(:media_asset, "must belong to the message listing")
    end
  end
end
