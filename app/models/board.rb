class Board < ApplicationRecord
  KINDS = %w[production internal custom].freeze

  belongs_to :organization
  belongs_to :created_by, class_name: "User", optional: true
  has_many :board_memberships, dependent: :destroy
  has_many :board_labels, dependent: :destroy
  has_many :workflow_columns, dependent: :destroy
  has_many :workflow_tasks, dependent: :destroy
  has_many :board_attachments, dependent: :destroy

  enum :kind, KINDS.index_by(&:itself), validate: true
  enum :visibility, { organization: "organization", restricted: "restricted" },
       prefix: :visible_to, validate: true

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :organization_id },
                   format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }

  before_validation :assign_slug, on: :create

  scope :active, -> { where(archived: false) }
  scope :ordered, -> { order(:position, :id) }

  def member_ids_for(member_type)
    board_memberships.where(member_type:).pluck(:member_id)
  end

  def assignable_user?(user)
    return false unless user&.internal? && user.organization_id == organization_id
    return true if visible_to_organization?

    board_memberships.where(member_type: "User", member_id: user.id).exists? ||
      board_memberships.where(member_type: "UserGroup", member_id: user.user_group_ids).exists?
  end

  private

  def assign_slug
    return if slug.present? || name.blank? || organization.blank?

    base = name.parameterize.presence || "board"
    candidate = base
    suffix = 2
    while organization.boards.where(slug: candidate).exists?
      candidate = "#{base}-#{suffix}"
      suffix += 1
    end
    self.slug = candidate
  end
end
