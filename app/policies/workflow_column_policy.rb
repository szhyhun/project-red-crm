# A column has no access rules of its own: it is part of a board's
# configuration, so every question is answered by the board it belongs to.
class WorkflowColumnPolicy < ApplicationPolicy
  def view?
    board_policy.view?
  end

  def index?
    user.internal?
  end

  def create?
    board_policy.manage?
  end

  def update?
    board_policy.manage?
  end

  def destroy?
    board_policy.manage?
  end

  def manage?
    board_policy.manage?
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
