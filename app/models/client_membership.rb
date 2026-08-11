class ClientMembership < ApplicationRecord
  belongs_to :client_account
  belongs_to :user

  enum :role, { admin: "admin", member: "member" }, validate: true

  validate :same_organization

  private

  def same_organization
    return if client_account.blank? || user.blank? || client_account.organization_id == user.organization_id

    errors.add(:user, "must belong to the client account organization")
  end
end
