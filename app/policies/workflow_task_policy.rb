class WorkflowTaskPolicy < OrganizationRecordPolicy
  def index?
    true
  end

  def create?
    user.organization_admin? || user.manager?
  end

  def update?
    belongs_to_current_organization? && (user.organization_admin? || user.manager? || record.assignee_id == user.id)
  end

  def destroy?
    belongs_to_current_organization? && (user.organization_admin? || user.manager?)
  end
end
