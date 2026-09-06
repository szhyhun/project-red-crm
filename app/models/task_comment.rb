class TaskComment < ApplicationRecord
  belongs_to :workflow_task
  belongs_to :author, class_name: "User"
  belongs_to :parent_comment, class_name: "TaskComment", optional: true
  has_many :board_attachments, dependent: :destroy
  has_many :replies, class_name: "TaskComment", foreign_key: :parent_comment_id, dependent: :destroy

  validates :body, presence: true
  validate :parent_belongs_to_same_task
  validate :parent_must_be_top_level
  before_validation :normalize_body_content

  scope :chronological, -> { order(:created_at, :id) }

  def edited?
    edited_at.present?
  end

  private

  def normalize_body_content
    return unless will_save_change_to_body_html?
    if body_html.blank?
      self.body_html = nil
      return
    end

    self.body_html = RichTextSanitizer.sanitize(body_html).presence
    self.body = RichTextSanitizer.plain_text(body_html)
  end

  def parent_belongs_to_same_task
    return if parent_comment.blank? || parent_comment.workflow_task_id == workflow_task_id

    errors.add(:parent_comment, "must belong to the same workflow task")
  end

  def parent_must_be_top_level
    return if parent_comment.blank? || parent_comment.parent_comment_id.blank?

    errors.add(:parent_comment, "cannot be a reply")
  end
end
