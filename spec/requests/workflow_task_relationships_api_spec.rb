require "rails_helper"

RSpec.describe "Workflow task relationship API", type: :request do
  let!(:organization) { Organization.create!(name: "Task relationship agency", slug: "task-relationship-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Task relationship manager", email: "task-relationship-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Task relationship client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "22 Relationship Street") }
  let!(:service) do
    organization.products.create!(slug: "relationship-photography", title: "Standard Property Photography",
                                  kind: :service, deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 29_900, sqft_min: 0, sqft_max: 1_000) }
  let!(:order) { Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later) }
  let!(:order_item) do
    order.order_items.create!(product: service, product_variant: variant, title: "Standard Property Photography",
                              quantity: 1, unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
  end
  let!(:deliverable) do
    order.order_deliverables.create!(organization:, listing:, order_item:, service_product: service,
                                     title: service.title, deliverable_type: service.deliverable_type,
                                     sla_days: service.sla_days, materialization_key: "relationship-deliverable")
  end
  let!(:home_board) { organization.default_board }
  let!(:review_board) do
    organization.boards.create!(name: "Relationship review", kind: :internal, visibility: :organization,
                                requires_listing: false, client_visible: false, position: 1).tap do |board|
      WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization:)) }
    end
  end
  let!(:parent_task) do
    home_board.workflow_tasks.create!(organization:, listing:, title: "Prepare listing delivery", status: "todo",
                                      task_kind: "parent")
  end
  let!(:child_task) do
    home_board.workflow_tasks.create!(organization:, listing:, parent_task: parent_task,
                                      title: "Prepare photography", status: "in_progress", task_kind: "deliverable")
  end

  before do
    child_task.workflow_task_placements.create!(board: review_board,
                                                workflow_column: review_board.workflow_columns.find_by!(key: "in_progress"),
                                                position: 3)
    child_task.workflow_task_deliverables.create!(order_deliverable: deliverable, position: 0)
    sign_in manager
  end

  it "returns placement and deliverable relationships on board cards" do
    get "/api/v1/boards/#{review_board.id}/workflow_tasks"

    expect(response).to have_http_status(:ok)
    serialized = response.parsed_body.fetch("workflow_tasks").sole

    expect(serialized).to include(
      "id" => child_task.id,
      "parent_task_id" => parent_task.id,
      "task_kind" => "deliverable",
      "board_id" => review_board.id,
      "status" => "in_progress"
    )
    expect(serialized.fetch("workflow_placements")).to contain_exactly(
      include("board_id" => home_board.id, "is_home" => true, "column_key" => "in_progress"),
      include("board_id" => review_board.id, "is_home" => false, "column_key" => "in_progress",
              "board_name" => "Relationship review")
    )
    expect(serialized.fetch("linked_deliverables")).to contain_exactly(
      include("id" => deliverable.id, "title" => "Standard Property Photography",
              "service_product" => include("id" => service.id, "title" => service.title))
    )
  end

  it "returns grouped child tasks and their relationships on the parent detail" do
    get "/api/v1/workflow_tasks/#{parent_task.id}"

    expect(response).to have_http_status(:ok)
    detail = response.parsed_body.fetch("workflow_task")
    child = detail.fetch("child_tasks").sole

    expect(child).to include(
      "id" => child_task.id,
      "parent_task_id" => parent_task.id,
      "task_kind" => "deliverable",
      "listing_address" => listing.address
    )
    expect(child.fetch("workflow_placements")).to include(
      include("board_id" => review_board.id, "column_name" => "In Progress")
    )
    expect(child.fetch("linked_deliverables").sole).to include("id" => deliverable.id)
  end

  it "does not expose a shared task through a board the current user cannot view" do
    restricted_board = organization.boards.create!(name: "Untrusted relationship board", kind: :internal,
                                                    visibility: :restricted, requires_listing: false,
                                                    client_visible: false, position: 2)
    WorkflowColumn::DEFAULTS.each { |attributes| restricted_board.workflow_columns.create!(attributes.merge(organization:)) }
    child_task.workflow_task_placements.create!(board: restricted_board,
                                                workflow_column: restricted_board.workflow_columns.find_by!(key: "todo"),
                                                position: 0)

    staff = organization.users.create!(name: "Untrusted staff", email: "task-relationship-staff@example.test",
                                       password: "long-enough-password", role: :production_staff)
    sign_out manager
    sign_in staff

    get "/api/v1/boards/#{restricted_board.id}/workflow_tasks"
    expect(response).to have_http_status(:not_found)
  end

  it "serializes only placements on boards the staff member can view" do
    home_board.update!(visibility: :restricted)
    review_board.update!(visibility: :restricted)
    staff = organization.users.create!(name: "Placement-visible staff", email: "placement-visible-staff@example.test",
                                       password: "long-enough-password", role: :production_staff)
    review_board.board_memberships.create!(member: staff, access: :viewer)
    secret_board = organization.boards.create!(name: "Secret relationship board", kind: :internal,
                                                visibility: :restricted, requires_listing: false,
                                                client_visible: false, position: 2)
    WorkflowColumn::DEFAULTS.each { |attributes| secret_board.workflow_columns.create!(attributes.merge(organization:)) }
    child_task.workflow_task_placements.create!(board: secret_board,
                                                workflow_column: secret_board.workflow_columns.find_by!(key: "in_progress"),
                                                position: 4)

    sign_out manager
    sign_in staff
    get "/api/v1/workflow_tasks/#{child_task.id}"

    expect(response).to have_http_status(:ok)
    serialized = response.parsed_body.fetch("workflow_task")
    expect(serialized.fetch("board_id")).to eq(review_board.id)
    expect(serialized.fetch("workflow_placements").map { |entry| entry.fetch("board_id") }).to eq([ review_board.id ])
    expect(serialized.fetch("workflow_placements").map { |entry| entry.fetch("board_name") }).not_to include("Secret relationship board")
  end
end
