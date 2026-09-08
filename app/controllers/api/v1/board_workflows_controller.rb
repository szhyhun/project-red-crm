class Api::V1::BoardWorkflowsController < Api::V1::BaseController
  before_action :set_board

  def index
    authorize @board, :manage?
    workflows = @board.board_workflows.includes(:conditions, :actions, :status_mappings).order(:name, :id)
    render json: { board_workflows: workflows.map { |workflow| serialize(workflow) } }
  end

  def show
    workflow = @board.board_workflows.includes(:conditions, :actions, :status_mappings, runs: :steps).find(params[:id])
    authorize workflow
    render json: { board_workflow: serialize(workflow, detailed: true) }
  end

  def create
    authorize @board, :manage?
    workflow = @board.board_workflows.build(workflow_params.merge(organization: Current.organization, created_by: current_user))
    if workflow.save
      render json: { board_workflow: serialize(workflow.reload, detailed: true) }, status: :created
    else
      render_validation_errors(workflow)
    end
  end

  def update
    workflow = @board.board_workflows.find(params[:id])
    authorize workflow, :manage?
    attributes = workflow_params
    workflow.workflow_version += 1 if attributes[:actions_attributes].present? || attributes[:conditions_attributes].present? || attributes[:status_mappings_attributes].present?
    if workflow.update(attributes)
      render json: { board_workflow: serialize(workflow.reload, detailed: true) }
    else
      render_validation_errors(workflow)
    end
  end

  def destroy
    workflow = @board.board_workflows.find(params[:id])
    authorize workflow, :manage?
    workflow.destroy!
    head :no_content
  end

  private

  def set_board
    @board = policy_scope(Board).find(params[:board_id])
  end

  def workflow_params
    params.require(:board_workflow).permit(
      :name, :description, :enabled, :trigger_key, :is_default,
      # Condition values are deliberately flexible JSON: the UI sends a scalar
      # for equals/not_equals and an array for in. Permit all three JSON shapes
      # so the value is not silently reduced to {} by ActionController.
      conditions_attributes: [ :id, :field, :operator, :position, :_destroy, :value, { value: [] }, { value: {} } ],
      actions_attributes: [ :id, :action_type, :position, :_destroy, { configuration: {} } ],
      status_mappings_attributes: %i[id source_status target_column_key position _destroy]
    ).to_h.deep_symbolize_keys
  end

  def serialize(workflow, detailed: false)
    data = workflow.slice(:id, :board_id, :name, :description, :enabled, :trigger_key, :is_default,
                          :workflow_version, :created_at, :updated_at).merge(
      conditions: workflow.conditions.ordered.map { |condition| condition.slice(:id, :field, :operator, :value, :position) },
      actions: workflow.actions.ordered.map { |action| action.slice(:id, :action_type, :configuration, :position) },
      status_mappings: workflow.status_mappings.order(:position, :id).map { |mapping| mapping.slice(:id, :source_status, :target_column_key, :position) }
    )
    return data unless detailed

    data.merge(runs: workflow.runs.recent.limit(20).map { |run| serialize_run(run) })
  end

  def serialize_run(run)
    run.slice(:id, :order_id, :idempotency_key, :status, :triggered_at, :started_at, :completed_at,
              :retry_count, :error, :metadata).merge(
      steps: run.steps.order(:position, :id).map { |step| step.slice(:id, :board_workflow_action_id, :status, :position, :input, :output, :error) }
    )
  end
end
