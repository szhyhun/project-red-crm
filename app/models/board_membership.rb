class BoardMembership < ApplicationRecord
  MEMBER_TYPES = %w[User UserGroup].freeze
  ACCESS_LEVELS = %w[viewer contributor manager].freeze

  belongs_to :board
  belongs_to :member, polymorphic: true

  enum :access, ACCESS_LEVELS.index_by(&:itself), prefix: :access, validate: true

  validates :member_type, inclusion: { in: MEMBER_TYPES }
  validates :member_id, uniqueness: { scope: %i[board_id member_type] }
  validate :member_belongs_to_board_organization

  private

  def member_belongs_to_board_organization
    return if member.blank? || board.blank?
    return if member.organization_id == board.organization_id

    errors.add(:member, "must belong to the same organization")
  end
end
