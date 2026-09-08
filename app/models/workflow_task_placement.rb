class WorkflowTaskPlacement < ApplicationRecord
  belongs_to :workflow_task
  belongs_to :board
  belongs_to :workflow_column

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :column_belongs_to_board
  validate :listing_present_when_board_requires_one
  validate :records_belong_to_same_organization

  scope :ordered, -> { order(:position, :id) }

  private

  def column_belongs_to_board
    return if workflow_column.blank? || workflow_column.board_id == board_id

    errors.add(:workflow_column, "must belong to the selected board")
  end

  def listing_present_when_board_requires_one
    return unless board.present? && board.requires_listing? && workflow_task&.listing_id.blank?

    errors.add(:workflow_task, "must have a listing on this board")
  end

  def records_belong_to_same_organization
    return if board.blank? || workflow_task.blank?
    return if board.organization_id == workflow_task.organization_id

    errors.add(:base, "task and board must belong to the same organization")
  end
end
