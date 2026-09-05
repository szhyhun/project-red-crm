class AppointmentPolicy < OrganizationRecordPolicy
  def index?
    user.internal?
  end

  def view?
    belongs_to_current_organization? && user.internal?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.internal?

      scope.where(organization_id: user.organization_id)
    end
  end
end
