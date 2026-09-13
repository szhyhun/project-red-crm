class Api::V1::WorkflowColumnsController < Api::V1::BaseController
  before_action :set_board

  def index
    authorize WorkflowColumn, :index?
    columns = @board.workflow_columns.ordered
    render json: { workflow_columns: columns.map { |column| serialize(column) } }
  end

  def create
    column = @board.workflow_columns.build(column_params.except(:position).merge(organization: Current.organization))
    column.position = normalized_position(column_params[:position], @board.workflow_columns.count)
    authorize column

    WorkflowColumn.transaction do
      column.save!
      place!(column, column.position)
    end
    render json: { workflow_column: serialize(column.reload) }, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def update
    column = scoped_columns.find(params[:id])
    authorize column
    target_position = normalized_position(column_params[:position], column.position)
    category_changed = column_params[:category].present? && column.category != column_params[:category]

    WorkflowColumn.transaction do
      column.update!(column_params.except(:position))
      place!(column, target_position)
      update_task_completion!(column) if category_changed
    end
    render json: { workflow_column: serialize(column.reload) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def destroy
    column = scoped_columns.find(params[:id])
    authorize column
    if column.board.workflow_columns.count == 1
      column.errors.add(:base, "A board must keep at least one column")
      return render_validation_errors(column)
    end

    placements = WorkflowTaskPlacement.where(board: column.board, workflow_column: column)
    home_tasks = column.board.workflow_tasks.where(status: column.key)
    replacement = replacement_column(column)
    if (home_tasks.exists? || placements.exists?) && replacement.blank?
      column.errors.add(:base, "Choose a replacement column for existing tasks")
      return render_validation_errors(column)
    end

    WorkflowColumn.transaction do
      relocate_tasks!(column, placements, home_tasks, replacement) if replacement
      column.destroy!
      compact_positions!(column.board)
    end
    head :no_content
  end

  private

  # Columns are always read through a board. Requests that predate board
  # scoping keep working by falling back to the organization's first board.
  def set_board
    @board = if params[:board_id].present?
      policy_scope(Board).find(params[:board_id])
    else
      policy_scope(Board).active.ordered.first
    end
    raise ActiveRecord::RecordNotFound, "no board available" if @board.blank?
  end

  def scoped_columns
    @board.workflow_columns
  end

  def column_params
    params.require(:workflow_column).permit(:name, :color, :category, :position)
  end

  def replacement_column(column)
    return if params[:replacement_column_id].blank?

    column.board.workflow_columns.where.not(id: column.id).find(params[:replacement_column_id])
  end

  def normalized_position(value, fallback)
    Integer(value.presence || fallback)
  rescue ArgumentError, TypeError
    fallback
  end

  def place!(column, target_position)
    columns = column.board.workflow_columns.where.not(id: column.id).ordered.to_a
    columns.insert(target_position.clamp(0, columns.length), column)
    columns.each_with_index { |item, position| item.update_columns(position:, updated_at: Time.current) }
  end

  # A deleted column may be used only by a secondary placement. Relocating the
  # task through the shared mover keeps the selected placement, home placement,
  # other board placements, completion timestamp, and linked deliverables in
  # the same canonical state.
  def relocate_tasks!(column, placements, home_tasks, replacement)
    placement_tasks = placements.includes(:workflow_task).order(:position, :id).map(&:workflow_task)
    tasks = (placement_tasks + home_tasks.order(:position, :id).to_a).uniq
    offset = replacement.board.workflow_task_placements.where(workflow_column: replacement).maximum(:position).to_i + 1

    tasks.each_with_index do |task, index|
      result = Workflows::MoveTask.call(
        task:,
        board: column.board,
        attributes: { status: replacement.key, position: offset + index }
      )
      raise result.failure.original_error || result.failure if result.failure?
    end
  end

  def compact_positions!(board)
    board.workflow_columns.ordered.each_with_index do |column, position|
      column.update_columns(position:, updated_at: Time.current)
    end
  end

  def update_task_completion!(column)
    completed_at = column.completed? ? Time.current : nil
    column.board.workflow_tasks.where(status: column.key).update_all(completed_at:, updated_at: Time.current)
  end

  def serialize(column)
    column.slice(:id, :key, :name, :color, :category, :position).merge(
      board_id: column.board_id,
      task_count: WorkflowTaskPlacement.where(board: column.board, workflow_column: column)
        .distinct.count(:workflow_task_id),
      capabilities: capabilities_for(column)
    )
  end
end
