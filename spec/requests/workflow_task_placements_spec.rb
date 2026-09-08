require "rails_helper"

RSpec.describe "Workflow task placement API", type: :request do
  let!(:organization) { Organization.create!(name: "Placement Agency", slug: "placement-agency") }
  let!(:other_organization) { Organization.create!(name: "Other Placement Agency", slug: "other-placement-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Placement Manager", email: "placement-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:staff) do
    User.create!(organization:, name: "Placement Staff", email: "placement-staff@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Placement Client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "3 Placement Street") }
  let!(:home_board) { organization.default_board }
  let!(:shared_board) do
    organization.boards.create!(name: "Shared Review", kind: :internal, visibility: :organization,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:task) do
    home_board.workflow_tasks.create!(organization:, listing:, title: "Review delivered media", status: "todo")
  end

  let(:service) do
    organization.products.create!(slug: "placement-photography", title: "Placement photography", kind: :service,
                                  deliverable_type: "photography")
  end
  let(:variant) { service.product_variants.create!(title: "Standard", price_cents: 10_000) }
  let(:order) { Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later) }
  let(:order_item) do
    order.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                              unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
  end
  let(:deliverable) do
    order.order_deliverables.create!(organization:, listing:, order_item:, service_product: service,
                                     title: service.title, deliverable_type: service.deliverable_type,
                                     materialization_key: "placement-deliverable-#{SecureRandom.uuid}")
  end

  before do
    task.workflow_task_placements.create!(board: shared_board,
                                          workflow_column: shared_board.workflow_columns.find_by!(key: "todo"),
                                          position: 0)
    sign_in manager
  end

  it "moves the home card and every shared placement to the matching canonical column" do
    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { status: "done", position: 0 }
    }

    expect(response).to have_http_status(:ok)
    expect(task.reload).to have_attributes(status: "done", completed_at: be_present)
    expect(task.workflow_task_placements.order(:board_id).map { |placement| [ placement.board_id, placement.workflow_column.key ] })
      .to contain_exactly([ home_board.id, "done" ], [ shared_board.id, "done" ])
    expect(task.activity_events.order(:created_at, :id).last.event_type).to eq("workflow_task.updated")
  end

  it "moves linked deliverables to delivered when a shared placement reaches done" do
    task.workflow_task_deliverables.create!(order_deliverable: deliverable, position: 0)

    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { board_id: shared_board.id, status: "done", position: 0 }
    }

    expect(response).to have_http_status(:ok)
    expect(deliverable.reload).to have_attributes(status: "delivered")
    expect(deliverable.delivered_at).to be_present
    expect(deliverable.activity_events.order(:created_at, :id).last).to have_attributes(
      event_type: "order_deliverable.status_changed"
    )
  end

  it "lists a shared task through the requested board placement" do
    get "/api/v1/boards/#{shared_board.id}/workflow_tasks"

    expect(response).to have_http_status(:ok)
    serialized = response.parsed_body.fetch("workflow_tasks").sole
    expect(serialized).to include(
      "id" => task.id,
      "board_id" => shared_board.id,
      "status" => "todo",
      "workflow_column_id" => shared_board.workflow_columns.find_by!(key: "todo").id,
      "placement_id" => task.workflow_task_placements.find_by!(board: shared_board).id
    )
  end

  it "orders cards by their placement on the selected board" do
    second_task = home_board.workflow_tasks.create!(organization:, listing:, title: "Second shared task", status: "todo", position: 1)
    second_task.workflow_task_placements.create!(
      board: shared_board,
      workflow_column: shared_board.workflow_columns.find_by!(key: "todo"),
      position: 0
    )
    task.workflow_task_placements.find_by!(board: shared_board).update!(position: 1)

    get "/api/v1/boards/#{shared_board.id}/workflow_tasks"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("workflow_tasks").pluck("id")).to eq([ second_task.id, task.id ])
  end

  it "lets an authorized restricted-board member move the shared placement" do
    home_board.update!(visibility: :restricted)
    shared_board.update!(visibility: :restricted)
    shared_board.board_memberships.create!(member: staff, access: "contributor")
    sign_out manager
    sign_in staff

    get "/api/v1/boards/#{shared_board.id}/workflow_tasks"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("workflow_tasks").pluck("id")).to eq([ task.id ])

    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { board_id: shared_board.id, status: "done", position: 0 }
    }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("workflow_task")).to include(
      "board_id" => shared_board.id,
      "status" => "done",
      "placement_id" => task.workflow_task_placements.find_by!(board: shared_board).id
    )
    expect(task.reload).to have_attributes(status: "done", completed_at: be_present)
    expect(task.workflow_task_placements.find_by!(board: home_board).workflow_column.key).to eq("done")
    expect(task.workflow_task_placements.find_by!(board: shared_board).workflow_column.key).to eq("done")
  end

  it "does not let a user move a task through a board where it has no placement" do
    third_board = organization.boards.create!(name: "Unrelated board", kind: :internal, visibility: :organization,
                                               requires_listing: false, client_visible: false, position: 2)
    WorkflowColumn::DEFAULTS.each { |attributes| third_board.workflow_columns.create!(attributes.merge(organization:)) }

    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { board_id: third_board.id, status: "done" }
    }

    expect(response).to have_http_status(:not_found)
    expect(task.reload.status).to eq("todo")
  end

  it "does not place a listingless task on a board that requires listings" do
    listing_required_board = organization.boards.create!(name: "Production intake", kind: :production,
                                                          visibility: :organization, requires_listing: true,
                                                          client_visible: true, position: 2).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
    listingless_task = shared_board.workflow_tasks.create!(organization:, title: "Internal task", status: "todo")
    listingless_task.workflow_task_placements.build(
      board: listing_required_board,
      workflow_column: listing_required_board.workflow_columns.find_by!(key: "todo"),
      position: 0
    ).save!(validate: false)

    expect do
      patch "/api/v1/workflow_tasks/#{listingless_task.id}", params: {
        workflow_task: { board_id: listing_required_board.id, status: "done", position: 0 }
      }
    end.not_to change { listingless_task.reload.status }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "workflow_task")).to include("must have a listing on this board")
  end

  it "does not let a staff member move a task on a board they cannot manage" do
    sign_out manager
    sign_in staff

    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { status: "done" }
    }

    expect(response).to have_http_status(:forbidden)
    expect(task.reload.status).to eq("todo")
  end

  it "does not expose a task or placement through another organization" do
    foreign_board = other_organization.default_board

    get "/api/v1/boards/#{foreign_board.id}/workflow_tasks"

    expect(response).to have_http_status(:not_found)
  end

  it "does not let a task update attach a listing from another organization" do
    foreign_client = ClientAccount.create!(organization: other_organization, name: "Foreign placement client", kind: :agent)
    foreign_listing = Listing.create!(organization: other_organization, client_account: foreign_client,
                                      address_line_1: "Foreign placement listing")

    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { listing_id: foreign_listing.id, title: "Attempted cross-tenant update" }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "listing")).to include("must belong to the same organization")
    expect(task.reload).to have_attributes(listing_id: listing.id, title: "Review delivered media")
  end

  it "rejects a requested status that is not a column on the task board" do
    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { status: "missing_column" }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "status")).to include("must match a column on this board")
    expect(task.reload.status).to eq("todo")
  end
end
