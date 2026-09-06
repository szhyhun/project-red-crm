require "rails_helper"
require Rails.root.join("db/migrate/20260906010000_remove_external_ref_from_workflow_tasks").to_s

RSpec.describe RemoveExternalRefFromWorkflowTasks, type: :migration do
  around do |example|
    ActiveRecord::Base.connection.transaction(requires_new: true) do
      described_class.new.down
      WorkflowTask.reset_column_information

      organization = Organization.create!(name: "Migration Org", slug: "migration-remove-task-reference")
      board = organization.boards.create!(name: "Legacy", slug: "legacy", kind: "internal", visibility: "organization",
                                          requires_listing: false, client_visible: false, position: 1)
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
      task = board.workflow_tasks.create!(organization:, title: "Obsolete plan reference", status: "todo")
      task.update_columns(external_ref: "T6")

      described_class.new.up
      WorkflowTask.reset_column_information

      example.run
      raise ActiveRecord::Rollback
    end
  end

  it "removes the documentation-only reference column" do
    expect(WorkflowTask.column_names).not_to include("external_ref")
  end
end
