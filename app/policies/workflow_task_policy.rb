class WorkflowTaskPolicy < ApplicationPolicy
  def view?
    board_policy.view?
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
    board_policy.update? || (board_policy.view? && record.assignee_id == user.id)
  end

  def destroy?
    board_policy.manage? || (board_policy.update? && user.manager?)
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.internal?

      scope.where(board_id: BoardPolicy::Scope.new(user, Board).resolve.select(:id))
    end
  end

  private

  def board_policy
    @board_policy ||= BoardPolicy.new(user, record.board)
  end
end
