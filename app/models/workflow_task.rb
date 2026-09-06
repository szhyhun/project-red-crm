class WorkflowTask < ApplicationRecord
  belongs_to :listing, optional: true
  belongs_to :organization
  belongs_to :board
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :reporter, class_name: "User", optional: true
  has_many :task_comments, dependent: :destroy
  has_many :task_checklist_items, dependent: :destroy
  has_many :board_attachments, dependent: :destroy
  has_many :activity_events, as: :subject, dependent: :destroy

  enum :priority, { low: "low", normal: "normal", high: "high", urgent: "urgent" }, validate: true

  validates :title, :status, presence: true
  validate :status_matches_board_column
  validate :listing_present_when_board_requires_one
  validate :assignee_can_work_on_board
  before_validation :normalize_description_content

  private

  def normalize_description_content
    return unless will_save_change_to_description_html?

    self.description_html = RichTextSanitizer.sanitize(description_html).presence
    self.description = RichTextSanitizer.plain_text(description_html).presence
  end

  def status_matches_board_column
    return if board.blank? || status.blank? || board.workflow_columns.where(key: status).exists?

    errors.add(:status, "must match a column on this board")
  end

  # Production boards track work against a property; internal boards track work
  # that has no property at all, so the requirement belongs to the board rather
  # than to the column.
  def listing_present_when_board_requires_one
    return if board.blank? || !board.requires_listing? || listing_id.present?

    errors.add(:listing, "is required on this board")
  end

  def assignee_can_work_on_board
    return if assignee.blank? || board.blank? || board.assignable_user?(assignee)

    errors.add(:assignee, "must have access to this board")
  end
end
