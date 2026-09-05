class WorkflowTask < ApplicationRecord
  belongs_to :listing, optional: true
  belongs_to :organization
  belongs_to :board
  belongs_to :assignee, class_name: "User", optional: true
  belongs_to :reporter, class_name: "User", optional: true

  enum :priority, { low: "low", normal: "normal", high: "high", urgent: "urgent" }, validate: true

  validates :title, :stage, :status, presence: true
  validate :status_matches_board_column
  validate :listing_present_when_board_requires_one

  private

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
end
