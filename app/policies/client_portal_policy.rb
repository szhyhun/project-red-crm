# Headless policy for the customer portal. It is the mirror of DashboardPolicy:
# internal staff use the dashboard, client users use the portal, and neither
# reaches the other.
class ClientPortalPolicy < ApplicationPolicy
  def view?
    !user.internal?
  end

  def update?
    view?
  end
end
