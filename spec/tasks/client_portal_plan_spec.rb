require "rake"
require "rails_helper"

load Rails.root.join("lib/tasks/client_portal_plan.rake").to_s unless Rake::Task.task_defined?("project_red:sync_plan_tasks")

RSpec.describe "project_red:sync_plan_tasks", type: :task do
  let!(:organization) { Organization.create!(name: "Plan Agency", slug: "plan-task-sync") }
  let!(:board) do
    organization.boards.create!(name: "CRM Development", kind: "internal", visibility: "organization",
                                requires_listing: false, client_visible: false, position: 1).tap do |created|
      WorkflowColumn::DEFAULTS.each { |attributes| created.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end

  before do
    Rake::Task["project_red:sync_plan_tasks"].reenable
    allow(Organization).to receive(:all).and_return(Organization.where(id: organization.id))
    allow(ENV).to receive(:fetch).with("BOARD_SLUG", "engineering").and_return(board.slug)
    allow(ENV).to receive(:[]).with("ORGANIZATION_SLUG").and_return(nil)
  end

  it "syncs plan labels through the board-owned label join" do
    Rake::Task["project_red:sync_plan_tasks"].invoke

    task = board.workflow_tasks.find_by!(external_ref: "T3")

    expect(task.board_labels.pluck(:name)).to contain_exactly("backend", "frontend", "schema")
    expect(task.board_labels.pluck(:board_id).uniq).to eq([ board.id ])
  end
end
