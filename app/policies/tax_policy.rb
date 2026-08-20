class TaxPolicy < OrganizationRecordPolicy
  def index?
    user.internal?
  end

  def destroy?
    update?
  end
end
