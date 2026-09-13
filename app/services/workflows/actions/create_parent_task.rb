module Workflows
  module Actions
    class CreateParentTask < ApplicationInteractor
      def call
        scope = context.fetch(:scope)
        action = context.fetch(:action)
        if scope.order.listing.blank? && scope.workflow.board.requires_listing?
          return context.set(:output, skipped: true, warning: "No listing is available for the parent task")
        end

        key = "workflow:#{scope.run.id}:parent"
        task = WorkflowTask.find_or_initialize_by(organization: scope.order.organization, workflow_group_key: key)
        task.assign_attributes(
          board: scope.workflow.board,
          listing: scope.order.listing,
          title: [ action.configuration["title"].presence || "Production", scope.order.listing&.address ].compact.join(" · "),
          status: scope.first_column_key(scope.workflow.board),
          task_kind: "parent",
          customer_visible: false,
          metadata: task.metadata.merge("workflow_run_id" => scope.run.id, "order_id" => scope.order.id)
        )
        task.save!
        context.set(:output, task_id: task.id)
      end
    end
  end
end
