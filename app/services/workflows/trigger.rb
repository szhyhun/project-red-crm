module Workflows
  class Trigger
    def initialize(order:)
      @order = order
    end

    def enqueue!
      @order.organization.board_workflows.enabled.for_trigger("order_approved").find_each do |workflow|
        next unless workflow.board.organization_id == @order.organization_id

        key = "order-#{@order.id}-workflow-#{workflow.id}-version-#{workflow.workflow_version}"
        run = BoardWorkflowRun.find_or_create_by!(idempotency_key: key) do |new_run|
          new_run.organization = @order.organization
          new_run.board_workflow = workflow
          new_run.order = @order
          new_run.triggered_at = Time.current
        end
        BoardWorkflowJob.perform_later(run.id) if run.pending? || run.failed?
      end
    end
  end
end
