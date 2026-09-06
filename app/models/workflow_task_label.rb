class WorkflowTaskLabel < ApplicationRecord
  belongs_to :workflow_task
  belongs_to :board_label

  validates :board_label_id, uniqueness: { scope: :workflow_task_id }
  validate :label_belongs_to_task_board

  private

  def label_belongs_to_task_board
    return if workflow_task.blank? || board_label.blank? || workflow_task.board_id == board_label.board_id

    errors.add(:board_label, "must belong to the task's board")
  end
end
