# Checklist items carry no authorship of their own: anyone who can move the
# task can tick its steps.
class TaskChecklistItemPolicy < ApplicationPolicy
  def view?
    task_policy.view?
  end

  def create?
    task_policy.update?
  end

  def update?
    task_policy.update?
  end

  def destroy?
    task_policy.update?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.internal?

      scope.where(workflow_task_id: WorkflowTaskPolicy::Scope.new(user, WorkflowTask).resolve.select(:id))
    end
  end

  private

  def task_policy
    @task_policy ||= WorkflowTaskPolicy.new(user, record.workflow_task)
  end
end
