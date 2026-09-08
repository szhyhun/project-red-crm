require "rails_helper"

RSpec.describe WorkflowTask, type: :model do
  let!(:organization) { Organization.create!(name: "Task integrity agency", slug: "task-integrity-agency") }
  let!(:other_organization) { Organization.create!(name: "Other task integrity agency", slug: "other-task-integrity-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Task integrity client", kind: :agent) }
  let!(:other_client_account) { ClientAccount.create!(organization: other_organization, name: "Other task client", kind: :agent) }
  let!(:foreign_listing) do
    Listing.create!(organization: other_organization, client_account: other_client_account,
                    address_line_1: "Foreign task listing")
  end
  let!(:board) { organization.default_board }

  it "rejects a listing from another organization" do
    task = board.workflow_tasks.build(organization:, listing: foreign_listing, title: "Cross-tenant task", status: "todo")

    expect(task).not_to be_valid
    expect(task.errors.full_messages).to include("Listing must belong to the same organization")
  end

  it "allows a listing from the task organization" do
    listing = Listing.create!(organization:, client_account:, address_line_1: "Local task listing")
    task = board.workflow_tasks.build(organization:, listing:, title: "Local task", status: "todo")

    expect(task).to be_valid
  end
end
