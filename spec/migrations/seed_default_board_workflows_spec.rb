require "rails_helper"
require_relative "../../db/migrate/20260907042000_seed_default_board_workflows"

RSpec.describe SeedDefaultBoardWorkflows, type: :migration do
  let!(:organization) { Organization.create!(name: "Seed workflow agency", slug: "seed-workflow-agency") }
  let!(:legacy_board) do
    organization.boards.create!(name: "Legacy Production", slug: "legacy-production", kind: :production,
                                visibility: :organization, requires_listing: true, client_visible: true, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end

  it "creates an idempotent default workflow with complete state mappings for legacy production boards" do
    migration = described_class.new

    expect { migration.up }.to change { legacy_board.board_workflows.count }.from(0).to(1)

    workflow = legacy_board.board_workflows.find_by!(is_default: true)
    expect(workflow).to be_enabled
    expect(workflow.actions.order(:position).pluck(:action_type)).to eq(
      %w[create_parent_task create_or_group_child_task place_on_board]
    )
    expect(workflow.status_mappings.order(:position).pluck(:source_status, :target_column_key)).to eq(
      [ [ "not_started", "todo" ], [ "in_progress", "in_progress" ],
        [ "in_review", "in_progress" ], [ "delivered", "done" ] ]
    )

    expect { migration.up }.not_to change { [ legacy_board.board_workflows.count, workflow.actions.count, workflow.status_mappings.count ] }
  end
end
