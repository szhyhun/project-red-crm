class UserGroup < ApplicationRecord
  belongs_to :organization
  has_many :user_group_memberships, dependent: :destroy
  has_many :users, through: :user_group_memberships
  has_many :board_memberships, as: :member, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :organization_id },
                   format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }

  before_validation :assign_slug, on: :create

  private

  def assign_slug
    return if slug.present? || name.blank? || organization.blank?

    base = name.parameterize.presence || "group"
    candidate = base
    suffix = 2
    while organization.user_groups.where(slug: candidate).exists?
      candidate = "#{base}-#{suffix}"
      suffix += 1
    end
    self.slug = candidate
  end
end
