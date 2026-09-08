class BoardWorkflowRunPolicy < OrganizationRecordPolicy
  def index?
    view?
  end

  def view?
    record.organization_id == user.organization_id && BoardWorkflowPolicy.new(user, record.board_workflow).view?
  end

  def update?
    record.organization_id == user.organization_id && BoardWorkflowPolicy.new(user, record.board_workflow).manage?
  end

  alias_method :create?, :update?
  alias_method :destroy?, :update?

  class Scope < Scope
    def resolve
      scope.where(organization_id: user.organization_id)
           .where(board_workflow_id: BoardWorkflowPolicy::Scope.new(user, BoardWorkflow).resolve.select(:id))
    end
  end
end
