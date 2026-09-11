class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :author, class_name: "User"
  has_many :conversation_attachments, dependent: :destroy
  has_many :message_media_references, dependent: :destroy
  has_many :referenced_media_assets, through: :message_media_references, source: :media_asset
  belongs_to :listing, optional: true
  belongs_to :order_deliverable, optional: true
  belongs_to :media_review, optional: true

  enum :message_kind, {
    message: "message",
    change_request: "change_request",
    review_notification: "review_notification"
  }, validate: true

  enum :visibility, { participants: "participants", staff_only: "staff_only" }, validate: true

  validates :body, presence: true
  before_validation :normalize_body_content
  validate :context_belongs_to_conversation

  private

  def normalize_body_content
    return unless will_save_change_to_body_html?
    if body_html.blank?
      self.body_html = nil
      return
    end

    self.body_html = RichTextSanitizer.sanitize(body_html).presence
    self.body = RichTextSanitizer.plain_text(body_html).presence
  end

  def context_belongs_to_conversation
    if listing.present? && listing.organization_id != conversation&.organization_id
      errors.add(:listing, "must belong to the conversation organization")
    end
    if order_deliverable.present? && order_deliverable.organization_id != conversation&.organization_id
      errors.add(:order_deliverable, "must belong to the conversation organization")
    end
    if media_review.present? && media_review.organization_id != conversation&.organization_id
      errors.add(:media_review, "must belong to the conversation organization")
    end
    if media_review.present? && listing.present? && media_review.listing_id != listing.id
      errors.add(:media_review, "must match the message listing")
    end
    if listing.present? && conversation&.client_account_id.present? && listing.client_account_id != conversation.client_account_id
      errors.add(:listing, "must belong to the selected customer account")
    end
  end
end
