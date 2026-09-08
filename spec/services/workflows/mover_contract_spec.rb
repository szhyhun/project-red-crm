require "rails_helper"

RSpec.describe WorkflowTasks::Mover, type: :service do
  let!(:organization) { Organization.create!(name: "Mover contract agency", slug: "mover-contract-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Mover client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "2 Mover Street") }
  let!(:home_board) { organization.default_board }
  let!(:shared_board) do
    organization.boards.create!(name: "Shared delivery", kind: :internal, visibility: :organization,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:review_columns) do
    [ home_board, shared_board ].map do |board|
      board.workflow_columns.create!(organization:, key: "review", name: "Review", color: "#f0c000",
                                     category: "active", position: 4)
    end
  end
  let!(:photo) do
    organization.products.create!(slug: "mover-photo", title: "Mover photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:video) do
    organization.products.create!(slug: "mover-video", title: "Mover video", kind: :service,
                                  deliverable_type: "video", sla_days: 3)
  end
  let!(:photo_variant) { photo.product_variants.create!(title: "Photo", price_cents: 20_000) }
  let!(:video_variant) { video.product_variants.create!(title: "Video", price_cents: 30_000) }
  let!(:order) { Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later) }
  let!(:photo_item) do
    order.order_items.create!(product: photo, product_variant: photo_variant, title: photo.title, quantity: 1,
                              unit_price_cents: photo_variant.price_cents, total_cents: photo_variant.price_cents)
  end
  let!(:video_item) do
    order.order_items.create!(product: video, product_variant: video_variant, title: video.title, quantity: 1,
                              unit_price_cents: video_variant.price_cents, total_cents: video_variant.price_cents)
  end
  let!(:photo_deliverable) do
    order.order_deliverables.create!(organization:, listing:, order_item: photo_item, service_product: photo,
                                     title: photo.title, deliverable_type: "photography", sla_days: 2,
                                     materialization_key: "mover-photo-#{SecureRandom.uuid}")
  end
  let!(:video_deliverable) do
    order.order_deliverables.create!(organization:, listing:, order_item: video_item, service_product: video,
                                     title: video.title, deliverable_type: "video", sla_days: 3,
                                     materialization_key: "mover-video-#{SecureRandom.uuid}")
  end
  let!(:task) do
    home_board.workflow_tasks.create!(organization:, listing:, title: "Grouped delivery", status: "todo", position: 1)
  end
  let!(:shared_placement) do
    task.workflow_task_placements.create!(board: shared_board,
                                          workflow_column: shared_board.workflow_columns.find_by!(key: "todo"),
                                          position: 1, is_home: false)
  end

  before do
    task.workflow_task_deliverables.create!(order_deliverable: photo_deliverable, position: 0)
    task.workflow_task_deliverables.create!(order_deliverable: video_deliverable, position: 1)
  end

  def move(board:, attributes:)
    WorkflowTasks::Mover.new(task:, board:, attributes:).move!
  end

  it "rejects a move through a board where the task has no placement" do
    unrelated_board = organization.boards.create!(name: "Unrelated mover board", kind: :internal,
                                                   visibility: :organization, requires_listing: false,
                                                   client_visible: false, position: 2)
    WorkflowColumn::DEFAULTS.each { |attributes| unrelated_board.workflow_columns.create!(attributes.merge(organization:)) }

    expect { move(board: unrelated_board, attributes: { status: "done" }) }
      .to raise_error(ActiveRecord::RecordNotFound, "task is not placed on this board")
    expect(task.reload.status).to eq("todo")
    expect(shared_placement.reload.workflow_column.key).to eq("todo")
  end

  it "rejects an unknown target column without changing task or placement state" do
    expect { move(board: home_board, attributes: { status: "missing", position: 0 }) }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(task.reload).to have_attributes(status: "todo", position: 1)
    expect(task.home_placement.reload.workflow_column.key).to eq("todo")
  end

  it "maps a home-board review move to every shared placement and linked deliverable" do
    move(board: home_board, attributes: { status: "review", position: 0 })

    expect(task.reload).to have_attributes(status: "review", position: 0)
    expect(task.home_placement.workflow_column.key).to eq("review")
    expect(shared_placement.reload.workflow_column.key).to eq("review")
    expect([ photo_deliverable.reload.status, video_deliverable.reload.status ]).to all(eq("in_review"))
    expect(photo_deliverable.delivered_at).to be_nil
    expect(video_deliverable.delivered_at).to be_nil
    activity_count = photo_deliverable.activity_events.where(event_type: "order_deliverable.status_changed").count +
      video_deliverable.activity_events.where(event_type: "order_deliverable.status_changed").count
    expect(activity_count).to eq(2)
  end

  it "moves grouped deliverables to delivered when a shared placement reaches done" do
    move(board: shared_board, attributes: { status: "done", position: 0 })

    expect(task.reload.status).to eq("done")
    expect(task.home_placement.workflow_column.key).to eq("done")
    expect(shared_placement.reload.workflow_column.key).to eq("done")
    expect([ photo_deliverable.reload, video_deliverable.reload ]).to all(be_delivered)
    expect(photo_deliverable.delivered_at).to be_present
    expect(video_deliverable.delivered_at).to be_present
  end

  it "clamps a negative drag position and keeps sibling positions contiguous" do
    sibling = home_board.workflow_tasks.create!(organization:, listing:, title: "Earlier task", status: "todo", position: 0)

    move(board: home_board, attributes: { status: "todo", position: -10 })

    expect(task.reload.position).to eq(0)
    expect(sibling.reload.position).to eq(1)
    expect(home_board.workflow_tasks.where(status: "todo").order(:position).pluck(:position)).to eq([ 0, 1 ])
  end

  it "does not create delivery status activity when a move keeps the same state" do
    expect { move(board: home_board, attributes: { status: "todo", position: 1 }) }
      .not_to change { ActivityEvent.where(subject: photo_deliverable).count + ActivityEvent.where(subject: video_deliverable).count }

    expect(photo_deliverable.reload).to be_not_started
    expect(video_deliverable.reload).to be_not_started
  end
end
