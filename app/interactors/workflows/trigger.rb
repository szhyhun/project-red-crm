module Workflows
  # Creates the idempotent workflow runs that follow a business event. Queueing
  # is part of this action because a run is the durable boundary between the
  # committed event and background execution.
  class Trigger < ApplicationInteractor
    TRIGGER_KEY = "order_approved"

    def call
      order = context.fetch(:order)
      runs = []

      order.organization.board_workflows.enabled.for_trigger(TRIGGER_KEY).find_each do |workflow|
        next unless workflow.board.organization_id == order.organization_id

        key = "order-#{order.id}-workflow-#{workflow.id}-version-#{workflow.workflow_version}"
        run = BoardWorkflowRun.find_or_create_by!(idempotency_key: key) do |new_run|
          new_run.organization = order.organization
          new_run.board_workflow = workflow
          new_run.order = order
          new_run.triggered_at = Time.current
        end
        runs << run
        BoardWorkflowJob.perform_later(run.id) if run.pending? || run.failed?
      end

      context.set(:order, order).set(:runs, runs)
    end
  end
end
