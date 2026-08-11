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
    task = listing.workflow_tasks.build(task_params.merge(organization: Current.organization))
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

    if task.update(task_params)
      task.update!(completed_at: Time.current) if task.done? && task.completed_at.nil?
      render json: { workflow_task: serialize(task) }
    else
      render_validation_errors(task)
    end
  end

  private

  def task_params
    params.require(:workflow_task).permit(:title, :status, :stage, :assignee_id, :customer_visible, :position, :due_at)
  end

  def serialize(task)
    data = task.slice(:id, :listing_id, :title, :status, :stage, :customer_visible, :position, :due_at, :completed_at).merge(listing_address: task.listing.address)
    return data unless current_user.internal?

    data.merge(assignee_id: task.assignee_id, assignee: task.assignee && task.assignee.slice(:id, :name, :role))
  end
end
