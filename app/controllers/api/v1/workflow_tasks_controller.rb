class Api::V1::WorkflowTasksController < Api::V1::BaseController
  def index
    if params[:listing_id].present?
      listing = policy_scope(Listing).find(params[:listing_id])
      authorize listing, :show?
      tasks = listing.workflow_tasks.includes(:assignee).order(:position)
      tasks = tasks.where(customer_visible: true) unless current_user.internal?
    else
      authorize WorkflowTask, :index?
      tasks = policy_scope(WorkflowTask).includes(:listing, :assignee).order(:status, :position, :created_at)
    end

    render json: { workflow_tasks: tasks.map { |task| serialize(task) } }
  end

  def create
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :update?
    attributes = task_params
    attributes[:status] = Current.organization.workflow_columns.ordered.first&.key if attributes[:status].blank?
    task = listing.workflow_tasks.build(attributes.merge(organization: Current.organization))
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

  def task_params
    params.require(:workflow_task).permit(:title, :description, :status, :stage, :assignee_id, :customer_visible, :position, :due_at, :priority)
  end

  def serialize(task)
    column = workflow_columns_by_key[task.status]
    data = task.slice(:id, :listing_id, :title, :description, :status, :stage, :priority, :customer_visible, :position, :due_at, :completed_at).merge(
      listing_address: task.listing.address,
      workflow_column_id: column&.id,
      column_category: column&.category
    )
    return data unless current_user.internal?

    data.merge(assignee_id: task.assignee_id, assignee: task.assignee && task.assignee.slice(:id, :name, :email, :role))
  end

  def workflow_columns_by_key
    @workflow_columns_by_key ||= Current.organization.workflow_columns.index_by(&:key)
  end
end
