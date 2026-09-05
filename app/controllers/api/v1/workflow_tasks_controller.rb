class Api::V1::WorkflowTasksController < Api::V1::BaseController
  def index
    if params[:listing_id].present?
      listing = policy_scope(Listing).find(params[:listing_id])
      authorize listing, :view?
      tasks = if current_user.internal?
        policy_scope(WorkflowTask).where(listing_id: listing.id)
      else
        listing.workflow_tasks.where(customer_visible: true).where(board: Board.where(client_visible: true))
      end
      tasks = tasks.includes(:assignee, :board).order(:position)
    else
      authorize WorkflowTask, :index?
      tasks = policy_scope(WorkflowTask).includes(:listing, :assignee, :board)
      tasks = tasks.where(board_id: params[:board_id]) if params[:board_id].present?
      tasks = tasks.order(:board_id, :status, :position, :created_at)
    end

    render json: { workflow_tasks: tasks.map { |task| serialize(task) } }
  end

  def create
    board = resolve_board
    listing = resolve_listing(board)
    attributes = task_params
    attributes[:status] = board.workflow_columns.ordered.first&.key if attributes[:status].blank?

    task = board.workflow_tasks.build(
      attributes.merge(organization: Current.organization, listing:, reporter: current_user)
    )
    authorize task

    if task.save
      render json: { workflow_task: serialize(task) }, status: :created
    else
      render_validation_errors(task)
    end
  end

  def update
    task = policy_scope(WorkflowTask).find(params[:id])
    authorize task

    WorkflowTasks::Mover.new(task:, attributes: task_params).move!
    render json: { workflow_task: serialize(task.reload) }
  rescue ActiveRecord::RecordInvalid => error
    render_validation_errors(error.record)
  end

  def destroy
    task = policy_scope(WorkflowTask).find(params[:id])
    authorize task
    task.destroy!
    head :no_content
  end

  private

  # A task can be created from its board or, as before boards existed, from a
  # listing. The listing route resolves to the organization's default board so
  # existing clients keep working unchanged.
  def resolve_board
    return policy_scope(Board).find(params[:board_id]) if params[:board_id].present?

    board = policy_scope(Board).active.ordered.first
    raise ActiveRecord::RecordNotFound, "no board available" if board.blank?

    board
  end

  def resolve_listing(board)
    listing_id = params[:listing_id].presence || task_params[:listing_id]
    return if listing_id.blank? && !board.requires_listing?

    listing = policy_scope(Listing).find(listing_id) if listing_id.present?
    authorize listing, :update? if listing.present?
    listing
  end

  def task_params
    params.require(:workflow_task).permit(
      :title, :description, :status, :stage, :assignee_id, :customer_visible,
      :position, :due_at, :priority, :listing_id, :external_ref, labels: []
    )
  end

  def serialize(task)
    column = columns_by_board_and_key[[ task.board_id, task.status ]]
    data = task.slice(:id, :board_id, :listing_id, :title, :description, :status, :stage, :priority,
                      :customer_visible, :position, :due_at, :completed_at, :labels, :external_ref).merge(
      listing_address: task.listing&.address,
      workflow_column_id: column&.id,
      column_category: column&.category
    )
    return data unless current_user.internal?

    data.merge(
      assignee_id: task.assignee_id,
      assignee: task.assignee && task.assignee.slice(:id, :name, :email, :role),
      capabilities: capabilities_for(task)
    )
  end

  def columns_by_board_and_key
    @columns_by_board_and_key ||= Current.organization.workflow_columns.index_by { |column| [ column.board_id, column.key ] }
  end
end
