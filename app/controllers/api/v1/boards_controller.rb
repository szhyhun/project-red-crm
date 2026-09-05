class Api::V1::BoardsController < Api::V1::BaseController
  def index
    boards = policy_scope(Board).active.ordered.includes(:board_memberships)
    render json: { boards: boards.map { |board| serialize(board) } }
  end

  def show
    board = policy_scope(Board).find(params[:id])
    authorize board
    render json: { board: serialize(board, detailed: true) }
  end

  def create
    board = Current.organization.boards.build(board_params.merge(created_by: current_user))
    board.position = Current.organization.boards.maximum(:position).to_i + 1 if board_params[:position].blank?
    authorize board

    if board.save
      create_default_columns!(board)
      render json: { board: serialize(board.reload, detailed: true) }, status: :created
    else
      render_validation_errors(board)
    end
  end

  def update
    board = policy_scope(Board).find(params[:id])
    authorize board, :manage?

    if board.update(board_params)
      render json: { board: serialize(board.reload, detailed: true) }
    else
      render_validation_errors(board)
    end
  end

  # Archiving keeps the board's task history readable. A board is only removed
  # outright while it is still empty.
  def destroy
    board = policy_scope(Board).find(params[:id])
    authorize board

    if Current.organization.boards.active.count == 1
      board.errors.add(:base, "An organization must keep at least one active board")
      return render_validation_errors(board)
    end

    board.workflow_tasks.none? ? board.destroy! : board.update!(archived: true)
    head :no_content
  end

  private

  def board_params
    params.require(:board).permit(:name, :slug, :description, :kind, :visibility,
                                  :requires_listing, :client_visible, :archived, :position)
  end

  def create_default_columns!(board)
    WorkflowColumn::DEFAULTS.each do |attributes|
      board.workflow_columns.create!(attributes.merge(organization: Current.organization))
    end
  end

  def serialize(board, detailed: false)
    data = board.slice(:id, :name, :slug, :description, :kind, :visibility, :requires_listing,
                       :client_visible, :archived, :position).merge(
      task_count: board.workflow_tasks.count,
      capabilities: capabilities_for(board)
    )
    return data unless detailed

    data.merge(members: board.board_memberships.map { |membership| serialize_membership(membership) })
  end

  def serialize_membership(membership)
    membership.slice(:id, :member_type, :member_id, :access).merge(
      name: membership.member&.name
    )
  end
end
