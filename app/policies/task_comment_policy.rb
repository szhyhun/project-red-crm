# A comment inherits the task's board access, with one addition: an author can
# edit and delete their own comment even where they could not touch anyone
# else's. A shared task may have more than one board, so use the first board
# where the current user can perform the requested action instead of assuming
# the task's home board is the only access path.
class TaskCommentPolicy < ApplicationPolicy
  def view?
    task_policy.view?
  end

  def create?
    task_policy.view? && board_policies.any?(&:update?)
  end

  def update?
    own? && create?
  end

  def destroy?
    return false unless task_policy.view?

    own? || board_policies.any?(&:manage?)
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.internal?

      scope.where(workflow_task_id: WorkflowTaskPolicy::Scope.new(user, WorkflowTask).resolve.select(:id))
    end
  end

  private

  def own?
    record.author_id == user.id
  end

  def task_policy
    @task_policy ||= WorkflowTaskPolicy.new(user, record.workflow_task)
  end

  def board_policies
    @board_policies ||= begin
      task = record.workflow_task
      boards = [ task.board ] + task.workflow_task_placements.includes(:board).map(&:board)
      boards.compact.uniq.map { |board| BoardPolicy.new(user, board) }
    end
  end
end
