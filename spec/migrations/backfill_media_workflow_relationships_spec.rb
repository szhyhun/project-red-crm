require "rails_helper"
require_relative "../../db/migrate/20260907041000_backfill_media_workflow_relationships"

RSpec.describe BackfillMediaWorkflowRelationships do
  let!(:organization) { Organization.create!(name: "Migration Agency", slug: "migration-workflow") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Migration Client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "Migration Street") }
  let!(:task) do
    organization.default_board.workflow_tasks.create!(
      organization:, listing:, title: "Existing task", status: "todo"
    )
  end

  it "backfills a home placement for an existing task row and can be rerun" do
    task.workflow_task_placements.delete_all
    migration = described_class.new

    ActiveRecord::Base.connection.remove_index(:conversations, name: "index_one_client_conversation_per_account")
    migration.up
    ActiveRecord::Base.connection.remove_index(:conversations, name: "index_one_client_conversation_per_account")
    migration.up

    expect(task.reload.home_placement).to have_attributes(
      board_id: organization.default_board.id,
      workflow_column_id: organization.default_board.workflow_columns.find_by!(key: "todo").id,
      is_home: true
    )
    expect(task.workflow_task_placements.count).to eq(1)
  end
end
