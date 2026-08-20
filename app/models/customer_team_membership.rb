class CustomerTeamMembership < ApplicationRecord
  belongs_to :customer_team
  belongs_to :client_account

  validates :client_account_id, uniqueness: { scope: :customer_team_id }
  validate :same_organization

  private

  def same_organization
    return if customer_team.blank? || client_account.blank? || customer_team.organization_id == client_account.organization_id

    errors.add(:client_account, "must belong to the customer team organization")
  end
end
