class MediaReviewComment < ApplicationRecord
  STATUSES = %w[draft published].freeze

  belongs_to :media_review_thread
  belongs_to :author, class_name: "User"

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :body, presence: true
  validate :author_belongs_to_review_organization
  before_validation :normalize_body_content

  private

  def normalize_body_content
    unless will_save_change_to_body_html?
      # A plain-text edit replaces the rich text too; otherwise the old HTML
      # keeps rendering in place of the edit.
      self.body_html = nil if will_save_change_to_body? && body_html.present?
      return
    end

    if body_html.blank?
      self.body_html = nil
      return
    end

    self.body_html = RichTextSanitizer.sanitize(body_html).presence
    self.body = RichTextSanitizer.plain_text(body_html).presence
  end

  def author_belongs_to_review_organization
    return if author.blank? || media_review_thread.blank? || media_review_thread.media_review.blank?
    return if author.organization_id == media_review_thread.media_review.organization_id

    errors.add(:author, "must belong to the review organization")
  end
end
