module Workflows
  module Actions
    class CreateChildTasks < ApplicationInteractor
      def call
        scope = context.fetch(:scope)
        action = context.fetch(:action)
        if scope.order.listing.blank? && scope.workflow.board.requires_listing?
          return context.set(:output, skipped: true, warning: "No listing is available for deliverable tasks")
        end

        parent = WorkflowTask.find_by(organization: scope.order.organization,
                                      workflow_group_key: "workflow:#{scope.run.id}:parent")
        tasks = scope.matching_deliverables.map do |deliverable|
          key = "deliverable:#{deliverable.materialization_key}"
          task = WorkflowTask.find_or_initialize_by(organization: scope.order.organization, workflow_group_key: key)
          task.assign_attributes(
            board: scope.workflow.board,
            parent_task: parent,
            listing: deliverable.listing,
            title: deliverable.title,
            description: deliverable.description,
            status: scope.initial_task_status(deliverable),
            task_kind: "deliverable",
            customer_visible: ActiveModel::Type::Boolean.new.cast(action.configuration.fetch("customer_visible", true)),
            metadata: task.metadata.merge("order_deliverable_id" => deliverable.id, "materialization_key" => deliverable.materialization_key)
          )
          task.save!
          task.workflow_task_deliverables.find_or_create_by!(order_deliverable: deliverable, position: deliverable.position)
          task
        end
        context.set(:output, task_ids: tasks.map(&:id), deliverable_ids: scope.matching_deliverables.map(&:id))
      end
    end
  end
end
