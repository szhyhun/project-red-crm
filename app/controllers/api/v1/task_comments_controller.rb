class Api::V1::TaskCommentsController < Api::V1::BaseController
  before_action :set_task

  def create
    comment = @task.task_comments.build(comment_params.merge(author: current_user))
    authorize comment

    if comment.save
      render json: { task_comment: serialize(comment) }, status: :created
    else
      render_validation_errors(comment)
    end
  end

  def update
    comment = @task.task_comments.find(params[:id])
    authorize comment

    if comment.update(comment_params.merge(edited_at: Time.current))
      render json: { task_comment: serialize(comment) }
    else
      render_validation_errors(comment)
    end
  end

  def destroy
    comment = @task.task_comments.find(params[:id])
    authorize comment
    comment.destroy!
    head :no_content
  end

  private

  def set_task
    @task = policy_scope(WorkflowTask).find(params[:workflow_task_id])
  end

  def comment_params
    params.require(:task_comment).permit(:body)
  end

  def serialize(comment)
    Api::V1::WorkflowTasksController.serialize_comment(comment, capabilities: capabilities_for(comment))
  end
end
