class Api::V1::WorkflowTasksController < Api::V1::BaseController
  def index
    listing = policy_scope(Listing).find(params[:listing_id])
    authorize listing, :show?
    render json: { workflow_tasks: listing.workflow_tasks.order(:position).map { |task| serialize(task) } }
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
    task.slice(:id, :title, :status, :stage, :assignee_id, :customer_visible, :position, :due_at, :completed_at)
  end
end
