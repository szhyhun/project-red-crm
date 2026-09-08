class BoardWorkflowRunStep < ApplicationRecord
  STATUSES = %w[pending running succeeded skipped failed].freeze

  belongs_to :board_workflow_run
  belongs_to :board_workflow_action

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :action_belongs_to_run_workflow

  private

  def action_belongs_to_run_workflow
    return if board_workflow_run.blank? || board_workflow_action.blank?
    return if board_workflow_run.board_workflow_id == board_workflow_action.board_workflow_id

    errors.add(:board_workflow_action, "must belong to the run workflow")
  end
end
