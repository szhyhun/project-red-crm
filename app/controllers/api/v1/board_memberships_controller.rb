class Api::V1::BoardMembershipsController < Api::V1::BaseController
  before_action :set_board

  def index
    authorize @board, :view?
    render json: { members: @board.board_memberships.map { |membership| serialize(membership) } }
  end

  def create
    authorize @board, :manage?
    membership = @board.board_memberships.build(membership_params)
    membership.member = resolve_member(membership_params[:member_type], membership_params[:member_id])

    if membership.member.present? && membership.save
      render json: { member: serialize(membership) }, status: :created
    else
      membership.errors.add(:member, "was not found in this organization") if membership.member.blank?
      render_validation_errors(membership)
    end
  end

  def destroy
    authorize @board, :manage?
    @board.board_memberships.find(params[:id]).destroy!
    head :no_content
  end

  private

  def set_board
    @board = policy_scope(Board).find(params[:board_id])
  end

  def membership_params
    params.require(:member).permit(:member_type, :member_id, :access)
  end

  # Members are looked up inside the board's own organization so a grant cannot
  # reach across tenants even if an id from another one is supplied.
  def resolve_member(member_type, member_id)
    case member_type
    when "User" then Current.organization.users.find_by(id: member_id)
    when "UserGroup" then Current.organization.user_groups.find_by(id: member_id)
    end
  end

  def serialize(membership)
    membership.slice(:id, :member_type, :member_id, :access).merge(name: membership.member&.name)
  end
end
