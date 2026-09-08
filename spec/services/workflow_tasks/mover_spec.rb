require "rails_helper"

RSpec.describe WorkflowTasks::Mover do
  let!(:organization) { Organization.create!(name: "Mover Agency", slug: "mover-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Mover Manager", email: "mover-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Mover Client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "2 Mover Street") }
  let!(:board) { organization.default_board }
  let!(:second_board) do
    organization.boards.create!(name: "Mover Internal", kind: :internal, visibility: :organization,
                                requires_listing: false, client_visible: false, position: 1).tap do |new_board|
      WorkflowColumn::DEFAULTS.each { |attributes| new_board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:service) do
    Product.create!(organization:, slug: "mover-service", title: "Mover service", kind: :service,
                    deliverable_type: "photography", sla_days: 1)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 10_000) }
  let!(:order) do
    Orders::Creator.new(
      organization:,
      attributes: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: variant.id, quantity: 1 } ]
      }
    ).create!
  end
  let!(:deliverable) do
    order.update!(status: :approved, approved_at: Time.current)
    Orders::DeliverableMaterializer.new(order:).call.sole
  end

  def task(title:, status: "todo", position: 0)
    board.workflow_tasks.create!(organization:, listing:, title:, status:, position:)
  end

  it "maps a completed board column to delivered and records the transition" do
    work = task(title: "Deliver the photos")
    work.workflow_task_deliverables.create!(order_deliverable: deliverable, position: 0)

    expect {
      described_class.new(task: work, attributes: { status: "done", position: 0 }).move!
    }.to change { deliverable.reload.status }.from("not_started").to("delivered")

    expect(work.reload).to have_attributes(status: "done")
    expect(work.completed_at).to be_present
    expect(deliverable.reload.delivered_at).to be_present
    expect(deliverable.activity_events.where(event_type: "order_deliverable.status_changed").last.payload).to include(
      "status" => "delivered", "workflow_task_id" => work.id
    )
  end

  it "moves a task between shared board placements when its canonical status changes" do
    work = task(title: "Shared delivery")
    second_todo = second_board.workflow_columns.find_by!(key: "todo")
    second_progress = second_board.workflow_columns.find_by!(key: "in_progress")
    work.workflow_task_placements.create!(board: second_board, workflow_column: second_todo,
                                          position: 0, is_home: false)

    described_class.new(task: work, attributes: { status: "in_progress", position: 0 }).move!

    expect(work.reload.home_placement).to have_attributes(board_id: board.id, workflow_column_id: board.workflow_columns.find_by!(key: "in_progress").id)
    expect(work.workflow_task_placements.find_by!(board: second_board)).to have_attributes(
      workflow_column_id: second_progress.id, is_home: false
    )
  end

  it "maps a review column on a shared board to the customer review state" do
    review = second_board.workflow_columns.create!(organization:, key: "review", name: "Review",
                                                   color: "#c9b6ff", category: "active", position: 4)
    work = task(title: "Review shared delivery")
    work.workflow_task_deliverables.create!(order_deliverable: deliverable, position: 0)
    work.workflow_task_placements.create!(board: second_board,
                                          workflow_column: second_board.workflow_columns.find_by!(key: "todo"),
                                          position: 0, is_home: false)

    described_class.new(task: work, board: second_board,
                        attributes: { status: review.key, position: 0 }).move!

    expect(work.reload.status).to eq("in_progress")
    expect(work.workflow_task_placements.find_by!(board: second_board).workflow_column).to eq(review)
    expect(deliverable.reload.status).to eq("in_review")
  end

  it "reorders siblings in the destination column" do
    first = task(title: "First", position: 0)
    second = task(title: "Second", position: 1)

    described_class.new(task: second, attributes: { status: "todo", position: 0 }).move!

    expect(first.reload.position).to eq(1)
    expect(second.reload.position).to eq(0)
  end

  it "clears completion when work returns from done" do
    work = task(title: "Reopened", status: "done")
    work.update!(completed_at: 1.day.ago)

    described_class.new(task: work, attributes: { status: "in_progress", position: 0 }).move!

    expect(work.reload).to have_attributes(status: "in_progress", completed_at: nil)
  end

  it "rejects a target status that is not a column on the task board" do
    work = task(title: "Keep valid")

    expect {
      described_class.new(task: work, attributes: { status: "missing" }).move!
    }.to raise_error(ActiveRecord::RecordInvalid, /must match a column on this board/)

    expect(work.reload.status).to eq("todo")
  end

  it "rejects a non-numeric position without changing the task" do
    work = task(title: "Keep position")

    expect {
      described_class.new(task: work, attributes: { status: "in_progress", position: "middle" }).move!
    }.to raise_error(ActiveRecord::RecordInvalid, /must be an integer/)

    expect(work.reload).to have_attributes(status: "todo", position: 0)
  end
end
