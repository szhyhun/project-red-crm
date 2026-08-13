class Api::V1::WorkflowColumnsController < Api::V1::BaseController
  def index
    authorize WorkflowColumn, :index?
    columns = policy_scope(WorkflowColumn).ordered
    render json: { workflow_columns: columns.map { |column| serialize(column) } }
  end

  def create
    column = Current.organization.workflow_columns.build(column_params.except(:position))
    column.position = normalized_position(column_params[:position], Current.organization.workflow_columns.count)
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
    column = policy_scope(WorkflowColumn).find(params[:id])
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
    column = policy_scope(WorkflowColumn).find(params[:id])
    authorize column
    if Current.organization.workflow_columns.count == 1
      column.errors.add(:base, "A board must keep at least one column")
      return render_validation_errors(column)
    end

    tasks = Current.organization.workflow_tasks.where(status: column.key)
    replacement = replacement_column(column)
    if tasks.exists? && replacement.blank?
      column.errors.add(:base, "Choose a replacement column for existing tasks")
      return render_validation_errors(column)
    end

    WorkflowColumn.transaction do
      move_tasks!(tasks, replacement) if replacement
      column.destroy!
      compact_positions!
    end
    head :no_content
  end

  private

  def column_params
    params.require(:workflow_column).permit(:name, :color, :category, :position)
  end

  def replacement_column(column)
    return if params[:replacement_column_id].blank?

    policy_scope(WorkflowColumn).where.not(id: column.id).find(params[:replacement_column_id])
  end

  def normalized_position(value, fallback)
    Integer(value.presence || fallback)
  rescue ArgumentError, TypeError
    fallback
  end

  def place!(column, target_position)
    columns = Current.organization.workflow_columns.where.not(id: column.id).ordered.to_a
    columns.insert(target_position.clamp(0, columns.length), column)
    columns.each_with_index { |item, position| item.update_columns(position:, updated_at: Time.current) }
  end

  # Reassigning with update_all kept each task's old position, so tasks arriving
  # from the deleted column collided with the positions already in use in the
  # replacement column. Duplicate positions make the board order arbitrary and
  # the next drag computes its target from a broken sequence, so they are
  # appended after whatever the replacement column already holds.
  def move_tasks!(tasks, replacement)
    completed_at = replacement.completed? ? Time.current : nil
    offset = Current.organization.workflow_tasks.where(status: replacement.key).maximum(:position).to_i + 1

    tasks.order(:position, :id).to_a.each_with_index do |task, index|
      task.update_columns(status: replacement.key, position: offset + index, completed_at:, updated_at: Time.current)
    end
  end

  def compact_positions!
    Current.organization.workflow_columns.ordered.each_with_index do |column, position|
      column.update_columns(position:, updated_at: Time.current)
    end
  end

  def update_task_completion!(column)
    completed_at = column.completed? ? Time.current : nil
    Current.organization.workflow_tasks.where(status: column.key).update_all(completed_at:, updated_at: Time.current)
  end

  def serialize(column)
    column.slice(:id, :key, :name, :color, :category, :position).merge(
      task_count: Current.organization.workflow_tasks.where(status: column.key).count
    )
  end
end
