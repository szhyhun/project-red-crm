class BoardWorkflowAction < ApplicationRecord
  ACTION_TYPES = %w[
    create_parent_task
    create_or_group_child_task
    place_on_board
    link_deliverable
    assign_to_user
    assign_to_group
  ].freeze

  belongs_to :board_workflow
  has_many :run_steps, class_name: "BoardWorkflowRunStep", dependent: :restrict_with_error

  validates :action_type, inclusion: { in: ACTION_TYPES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :target_belongs_to_workflow_organization
  validate :target_column_exists_on_target_board

  scope :ordered, -> { order(:position, :id) }

  private

  def target_belongs_to_workflow_organization
    target_class, target_id, target_name = case action_type
    when "place_on_board"
      [ Board, configuration.to_h["board_id"] || configuration.to_h[:board_id], "board" ]
    when "assign_to_user"
      [ User, configuration.to_h["user_id"] || configuration.to_h[:user_id], "user" ]
    when "assign_to_group"
      [ UserGroup, configuration.to_h["user_group_id"] || configuration.to_h[:user_group_id], "group" ]
    end
    return if target_class.blank? || target_id.blank?

    target = target_class.find_by(id: target_id)
    return if target.present? && target.organization_id == board_workflow&.organization_id

    errors.add(:configuration, "target #{target_name} must belong to the workflow organization")
  end

  def target_column_exists_on_target_board
    return unless action_type == "place_on_board"

    column_key = configuration.to_h["column_key"] || configuration.to_h[:column_key]
    return if column_key.blank?

    board_id = configuration.to_h["board_id"] || configuration.to_h[:board_id]
    target_board = if board_id.present?
      board_workflow&.organization&.boards&.find_by(id: board_id)
    else
      board_workflow&.board
    end
    return if target_board.blank? || target_board.workflow_columns.exists?(key: column_key)

    errors.add(:configuration, "target column must exist on the target board")
  end
end
