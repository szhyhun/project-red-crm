class Api::V1::BoardWorkflowRunsController < Api::V1::BaseController
  before_action :set_board

  def index
    authorize @board, :manage?
    runs = policy_scope(BoardWorkflowRun).where(board_workflows: { board_id: @board.id })
      .joins(:board_workflow).includes(:order, :steps).recent.limit(100)
    render json: { board_workflow_runs: runs.map { |run| serialize(run) } }
  end

  def retry
    run = policy_scope(BoardWorkflowRun).joins(:board_workflow).where(board_workflows: { board_id: @board.id }).find(params[:id])
    authorize run, :update?
    return render json: { error: "workflow_run_not_failed" }, status: :unprocessable_entity unless run.failed?

    run.update!(status: :pending, retry_count: run.retry_count + 1, completed_at: nil)
    BoardWorkflowJob.perform_later(run.id)
    render json: { board_workflow_run: serialize(run.reload) }, status: :accepted
  end

  private

  def set_board
    @board = policy_scope(Board).find(params[:board_id])
  end

  def serialize(run)
    run.slice(:id, :board_workflow_id, :order_id, :idempotency_key, :status, :triggered_at, :started_at,
              :completed_at, :retry_count, :error, :metadata).merge(
      steps: run.steps.order(:position, :id).map { |step| step.slice(:id, :board_workflow_action_id, :status, :position, :input, :output, :error) }
    )
  end
end
