# A comment inherits its board's access, with one addition: an author can edit
# and delete their own comment even where they could not touch anyone else's.
class TaskCommentPolicy < ApplicationPolicy
  def view?
    task_policy.view?
  end

  def create?
    task_policy.view? && board_policy.update?
  end

  def update?
    own? && create?
  end

  def destroy?
    return false unless task_policy.view?

    own? || board_policy.manage?
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

  def board_policy
    @board_policy ||= BoardPolicy.new(user, record.workflow_task.board)
  end
end
