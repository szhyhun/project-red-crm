class TravelFeePolicy < OrganizationRecordPolicy
  def index?
    user.internal?
  end

  def destroy?
    update?
  end
end
