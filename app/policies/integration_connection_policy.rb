class IntegrationConnectionPolicy < ApplicationPolicy
  def show?
    administrator?
  end

  def create?
    administrator?
  end

  def validate?
    administrator?
  end

  def import?
    administrator?
  end

  def destroy?
    administrator?
  end

  private

  def administrator?
    record.organization_id == user.organization_id && (user.organization_admin? || user.platform_owner?)
  end
end
