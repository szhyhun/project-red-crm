class BoardPolicy < ApplicationPolicy
  # Ranked so a grant can be compared with >= rather than by listing every
  # acceptable level at each call site.
  ACCESS_RANK = { "viewer" => 1, "contributor" => 2, "manager" => 3 }.freeze

  def view?
    return false unless internal_and_same_organization?

    admin? || record.visible_to_organization? || access_rank.positive?
  end

  def create?
    internal? && (user.admin? || user.manager?)
  end

  def update?
    return false unless internal_and_same_organization?

    admin? || (record.visible_to_organization? && user.manager?) || access_rank >= ACCESS_RANK["contributor"]
  end

  # Columns, membership grants and archiving. On a board the whole organization
  # can see, this stays with the existing role rules; a restricted board needs
  # an explicit manager grant. An organization admin always keeps it, because an
  # admin who cannot audit a board inside their own tenant is a support problem
  # rather than a privacy feature.
  def manage?
    return false unless internal_and_same_organization?

    admin? || (record.visible_to_organization? && user.manager?) || access_rank >= ACCESS_RANK["manager"]
  end

  def destroy?
    manage?
  end

  def access_rank
    ACCESS_RANK.fetch(granted_access, 0)
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.internal?

      boards = scope.where(organization_id: user.organization_id)
      return boards if user.admin?

      boards.where(
        "boards.visibility = 'organization' OR EXISTS (" \
        "SELECT 1 FROM board_memberships m WHERE m.board_id = boards.id AND (" \
        "(m.member_type = 'User' AND m.member_id = :user_id) OR " \
        "(m.member_type = 'UserGroup' AND m.member_id IN (:group_ids))))",
        user_id: user.id, group_ids: group_ids
      )
    end

    private

    # An empty IN () list is a syntax error, so an ungrouped user is compared
    # against an id no record can hold.
    def group_ids
      ids = user.user_group_ids
      ids.presence || [ -1 ]
    end
  end

  private

  def internal?
    user.internal?
  end

  def internal_and_same_organization?
    internal? && record.organization_id == user.organization_id
  end

  def admin?
    user.admin?
  end

  def granted_access
    @granted_access ||= record.board_memberships
      .where(member_type: "User", member_id: user.id)
      .or(record.board_memberships.where(member_type: "UserGroup", member_id: user.user_group_ids))
      .pluck(:access)
      .max_by { |access| ACCESS_RANK.fetch(access, 0) }
  end
end
