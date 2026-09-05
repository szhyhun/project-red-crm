class Api::V1::TaskChecklistItemsController < Api::V1::BaseController
  before_action :set_task

  def create
    item = @task.task_checklist_items.build(item_params)
    item.position = @task.task_checklist_items.maximum(:position).to_i + 1 if item_params[:position].blank?
    authorize item

    item.save ? render(json: { task_checklist_item: serialize(item) }, status: :created) : render_validation_errors(item)
  end

  def update
    item = @task.task_checklist_items.find(params[:id])
    authorize item
    item.assign_attributes(item_params)
    item.completed_by = current_user if item.completed_at_changed? && item.completed_at.present?

    item.save ? render(json: { task_checklist_item: serialize(item.reload) }) : render_validation_errors(item)
  end

  def destroy
    item = @task.task_checklist_items.find(params[:id])
    authorize item
    item.destroy!
    head :no_content
  end

  private

  def set_task
    @task = policy_scope(WorkflowTask).find(params[:workflow_task_id])
  end

  def item_params
    params.require(:task_checklist_item).permit(:title, :position, :done)
  end

  def serialize(item)
    Api::V1::WorkflowTasksController.serialize_checklist_item(item)
  end
end
