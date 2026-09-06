class Api::V1::TaskCommentsController < Api::V1::BaseController
  before_action :set_task

  def create
    attributes = comment_params
    parent = @task.task_comments.find(attributes[:parent_comment_id]) if attributes[:parent_comment_id].present?
    comment = @task.task_comments.build(attributes.except(:parent_comment_id).merge(author: current_user, parent_comment: parent))
    authorize comment

    if comment.save
      record_activity("task_comment.created", comment_id: comment.id, parent_comment_id: comment.parent_comment_id)
      render json: { task_comment: serialize(comment) }, status: :created
    else
      render_validation_errors(comment)
    end
  end

  def update
    comment = @task.task_comments.find(params[:id])
    authorize comment

    if comment.update(comment_params.merge(edited_at: Time.current))
      record_activity("task_comment.updated", comment_id: comment.id)
      render json: { task_comment: serialize(comment) }
    else
      render_validation_errors(comment)
    end
  end

  def destroy
    comment = @task.task_comments.find(params[:id])
    authorize comment
    record_activity("task_comment.deleted", comment_id: comment.id)
    comment.destroy!
    head :no_content
  end

  private

  def set_task
    @task = policy_scope(WorkflowTask).find(params[:workflow_task_id])
  end

  def comment_params
    params.require(:task_comment).permit(:body, :body_html, :parent_comment_id)
  end

  def serialize(comment)
    Api::V1::WorkflowTasksController.serialize_comment(comment, capabilities: capabilities_for(comment))
  end

  def record_activity(event_type, payload = {})
    ActivityEvent.create!(organization: Current.organization, actor: current_user, subject: @task, event_type:, payload:)
  end
end
