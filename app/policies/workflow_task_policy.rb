class WorkflowTaskPolicy < ApplicationPolicy
  def view?
    visible_on_any_authorized_board?
  end

  def index?
    user.internal?
  end

  def create?
    board_policy.update?
  end

  # An assignee can always move their own work, even on a board where they only
  # hold viewer access.
  def update?
    update_on_board?(record.board) || record.workflow_task_placements.any? { |placement| update_on_board?(placement.board) }
  end

  def destroy?
    board_policy.manage? || (board_policy.update? && user.manager?)
  end

  # A placement is a view onto the canonical task. The user must be allowed to
  # edit the selected board (or be the assignee with view access) before a move
  # can change the canonical task and all of its other placements.
  def update_on_board?(board)
    return false if board.blank? || board.organization_id != user.organization_id
    return false unless board.id == record.board_id || record.workflow_task_placements.exists?(board_id: board.id)

    board_policy_for(board).update? || (board_policy_for(board).view? && record.assignee_id == user.id)
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.internal?

      visible_board_ids = BoardPolicy::Scope.new(user, Board).resolve.select(:id)
      scope.where(board_id: visible_board_ids).or(
        scope.where(id: WorkflowTaskPlacement.where(board_id: visible_board_ids).select(:workflow_task_id))
      )
    end
  end

  private

  def board_policy
    @board_policy ||= board_policy_for(record.board)
  end

  def board_policy_for(board)
    BoardPolicy.new(user, board)
  end

  def visible_on_any_authorized_board?
    return true if board_policy.view?

    record.workflow_task_placements.any? do |placement|
      board_policy_for(placement.board).view?
    end
  end
end
