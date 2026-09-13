# A person subscribes their own browsers, and nobody else's.
class PushSubscriptionPolicy < ApplicationPolicy
  def create?
    true
  end

  def destroy?
    record.user_id == user.id
  end

  class Scope < Scope
    def resolve
      scope.where(user_id: user.id)
    end
  end
end
