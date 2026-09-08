class BoardWorkflowStatusMapping < ApplicationRecord
  SOURCE_STATUSES = OrderDeliverable::STATUSES.freeze

  belongs_to :board_workflow

  validates :source_status, inclusion: { in: SOURCE_STATUSES }
  validates :target_column_key, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :target_column_exists_on_workflow_board

  private

  def target_column_exists_on_workflow_board
    return if board_workflow.blank? || target_column_key.blank?
    return if board_workflow.board.workflow_columns.where(key: target_column_key).exists?

    errors.add(:target_column_key, "must match a column on the workflow board")
  end
end
