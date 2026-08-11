require "rails_helper"

RSpec.describe WorkflowTasks::Mover do
  it "moves a task and compacts both board columns" do
    organization = Organization.create!(name: "ProjectRed", slug: "projectred")
    client = ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent)
    listing = Listing.create!(organization:, client_account: client, address_line_1: "111 Oak Bay Avenue")
    first = WorkflowTask.create!(organization:, listing:, title: "Shoot", stage: "shoot", status: :todo, position: 0)
    moved = WorkflowTask.create!(organization:, listing:, title: "Edit", stage: "editing", status: :todo, position: 1)
    target = WorkflowTask.create!(organization:, listing:, title: "Review", stage: "review", status: :in_progress, position: 0)

    described_class.new(task: moved, attributes: { status: "in_progress", position: 0 }).move!

    expect(first.reload.position).to eq(0)
    expect(moved.reload).to have_attributes(status: "in_progress", position: 0)
    expect(target.reload.position).to eq(1)
  end

  it "reports malformed positions as validation errors" do
    organization = Organization.create!(name: "ProjectRed", slug: "projectred-invalid-position")
    client = ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent)
    listing = Listing.create!(organization:, client_account: client, address_line_1: "111 Oak Bay Avenue")
    task = WorkflowTask.create!(organization:, listing:, title: "Shoot", stage: "shoot", status: :todo, position: 0)

    expect { described_class.new(task:, attributes: { position: "not-a-number" }).move! }
      .to raise_error(ActiveRecord::RecordInvalid, /Position must be an integer/)
  end
end
