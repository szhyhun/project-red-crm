class ClientAccountTag < ApplicationRecord
  belongs_to :client_account
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :client_account_id }
  validate :same_organization

  private

  def same_organization
    return if client_account.blank? || tag.blank? || client_account.organization_id == tag.organization_id

    errors.add(:tag, "must belong to the same organization")
  end
end
