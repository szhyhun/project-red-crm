# Headless policy: the internal dashboard aggregates counts rather than exposing
# one record, so it authorizes against the resource name instead of an instance.
class DashboardPolicy < ApplicationPolicy
  def view?
    user.internal?
  end
end
