module Integrations::Aryeo::Actions::Tasks
  class ImportTask < ApplicationInteractor
      def call
        importer = context.fetch(:importer)
        payload = context.fetch(:payload)
        external = importer.task_external_id(payload)
        listing = importer.task_listing_for(payload)
        return context.set(:task, nil) if external.blank? || listing.blank?

        task = importer.task_record_for(external)
        task ||= importer.organization.workflow_tasks.build(listing:, metadata: { "aryeo_id" => external })
        task.assign_attributes(
          listing:,
          title: importer.task_value(payload, "title", "name").presence || "Aryeo task #{external}",
          description: importer.task_value(payload, "description", "notes"),
          assignee: importer.task_staff_for(payload),
          status: importer.task_workflow_status(payload),
          priority: importer.task_priority(payload),
          customer_visible: false,
          due_at: importer.task_time_value(payload, "due_at", "due_date"),
          completed_at: importer.task_time_value(payload, "completed_at"),
          origin: :aryeo,
          metadata: task.metadata.merge("aryeo_id" => external)
        )
        task.save!

        context.set(:task, task)
      end
  end
end
