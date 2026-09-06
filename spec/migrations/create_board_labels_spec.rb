require "rails_helper"
require Rails.root.join("db/migrate/20260905180000_create_board_labels").to_s

# This exercises the part of the migration that is easy to get wrong silently:
# existing task label strings must become board-owned records on the same board.
RSpec.describe CreateBoardLabels, type: :migration do
  around do |example|
    ActiveRecord::Base.connection.transaction(requires_new: true) do
      described_class.new.down
      WorkflowTask.reset_column_information

      organization = Organization.create!(name: "Migration Org", slug: "migration-board-labels")
      board = organization.boards.create!(name: "Legacy", slug: "legacy", kind: "internal", visibility: "organization",
                                          requires_listing: false, client_visible: false, position: 1)
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
      task = board.workflow_tasks.create!(organization:, title: "Legacy labels", status: "todo")
      task.update_columns(labels: %w[backend schema])

      described_class.new.up
      WorkflowTask.reset_column_information
      BoardLabel.reset_column_information
      WorkflowTaskLabel.reset_column_information
      @migrated_task = WorkflowTask.find(task.id)

      example.run
      raise ActiveRecord::Rollback
    end
  end

  it "backfills existing labels into the task's board label set" do
    expect(@migrated_task.board_labels.pluck(:name)).to contain_exactly("backend", "schema")
    expect(@migrated_task.board_labels.pluck(:board_id).uniq).to eq([ @migrated_task.board_id ])
  end
end
