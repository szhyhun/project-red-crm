class BoardWorkflowPolicy < OrganizationRecordPolicy
  def index?
    manageable_board?
  end

  def view?
    manageable_board?
  end

  def create?
    manageable_board?
  end

  alias_method :update?, :create?
  alias_method :destroy?, :create?
  alias_method :manage?, :create?

  class Scope < Scope
    def resolve
      scope.where(organization_id: user.organization_id).where(board_id: BoardPolicy::Scope.new(user, Board).resolve.select(:id))
    end
  end

  private

  def manageable_board?
    record.organization_id == user.organization_id && BoardPolicy.new(user, record.board).manage?
  end
end
