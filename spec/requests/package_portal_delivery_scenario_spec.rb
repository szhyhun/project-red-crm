require "rails_helper"

RSpec.describe "Package delivery portal scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Package portal agency", slug: "package-portal-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Package portal manager", email: "package-portal-manager@example.test",
                password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Package portal client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Package portal customer", email: "package-portal-client@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "18 Package Portal Street") }
  let!(:board) { organization.default_board }
  let!(:photography) do
    organization.products.create!(
      slug: "package-portal-photography",
      title: "Standard Property Photography",
      description: "Professional interior and exterior property photography.",
      kind: :service,
      deliverable_type: "photography",
      sla_days: 2
    )
  end
  let!(:video) do
    organization.products.create!(
      slug: "package-portal-video",
      title: "Property Video",
      description: "A professionally edited property video.",
      kind: :service,
      deliverable_type: "video",
      sla_days: 3
    )
  end
  let!(:package) do
    organization.products.create!(
      slug: "package-portal-complete",
      title: "Complete Media Package",
      description: "Photography and video for one property.",
      kind: :package,
      deliverable_type: "other",
      sla_days: 3
    )
  end
  let!(:package_variant) do
    package.product_variants.create!(
      title: "Up to 2,000 sqft",
      price_cents: 75_000,
      sqft_min: 0,
      sqft_max: 2_000
    )
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.where(is_default: true).update_all(enabled: false)
    allow(Conversations::NotifyJob).to receive(:perform_later)
    sign_in manager
  end

  it "keeps package services separate while approval, portal status, and change requests stay linked" do
    package.package_components.create!(
      organization:,
      service_product: photography,
      quantity: 1,
      position: 0
    )
    package.package_components.create!(
      organization:,
      service_product: video,
      quantity: 1,
      position: 1
    )

    post "/api/v1/boards/#{board.id}/workflows", params: {
      board_workflow: {
        name: "Package delivery workflow",
        trigger_key: "order_approved",
        enabled: true,
        status_mappings_attributes: BoardWorkflow.default_status_mapping_attributes(board),
        actions_attributes: [
          { action_type: "create_parent_task", configuration: {}, position: 0 },
          { action_type: "create_or_group_child_task", configuration: { customer_visible: true }, position: 1 },
          { action_type: "place_on_board", configuration: { board_id: board.id, column_key: "todo" }, position: 2 }
        ]
      }
    }
    expect(response).to have_http_status(:created)

    post "/api/v1/orders", params: {
      order: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: package_variant.id, quantity: 1 } ]
      }
    }
    expect(response).to have_http_status(:created)
    order_id = response.parsed_body.dig("order", "id")

    perform_enqueued_jobs(only: BoardWorkflowJob) do
      post "/api/v1/orders/#{order_id}/approve"
    end
    expect(response).to have_http_status(:ok)

    order = Order.find(order_id)
    deliverables = order.order_deliverables.ordered
    expect(deliverables.map(&:service_product)).to contain_exactly(photography, video)
    expect(deliverables.map(&:order_item_id)).to all(eq(order.order_items.sole.id))
    expect(order.invoices.sum(:total_cents)).to eq(0)
    expect(order.total_cents).to eq(75_000)
    expect(deliverables.map(&:scope_label)).to all(eq("0–2,000 sqft"))
    expect(deliverables.flat_map(&:workflow_tasks).size).to eq(2)

    photo_deliverable = deliverables.find { |item| item.service_product_id == photography.id }
    video_deliverable = deliverables.find { |item| item.service_product_id == video.id }
    photo_task = photo_deliverable.workflow_tasks.sole
    video_task = video_deliverable.workflow_tasks.sole

    photo_asset = MediaAsset.create!(
      organization:,
      listing:,
      order:,
      order_item: order.order_items.sole,
      order_deliverable: photo_deliverable,
      kind: :final,
      status: :ready,
      storage_key: "package-portal/#{photo_deliverable.id}/front.jpg",
      filename: "front.jpg",
      content_type: "image/jpeg",
      byte_size: 5,
      customer_visible: true,
      source_url: "https://cdn.example.test/front.jpg"
    )

    patch "/api/v1/workflow_tasks/#{photo_task.id}", params: {
      workflow_task: { status: "done", position: 0 }
    }
    expect(response).to have_http_status(:ok)
    expect(photo_deliverable.reload).to be_delivered
    expect(video_deliverable.reload).to be_not_started

    sign_out manager
    sign_in client_user
    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload.fetch("summary")).to include("deliverable_count" => 2, "delivered_count" => 1)
    expect(payload.fetch("deliverables")).to contain_exactly(
      hash_including(
        "id" => photo_deliverable.id,
        "title" => photography.title,
        "status" => "delivered",
        "asset_count" => 1,
        "can_request_changes" => true
      ),
      hash_including(
        "id" => video_deliverable.id,
        "title" => video.title,
        "status" => "not_started",
        "asset_count" => 0,
        "can_request_changes" => false
      )
    )
    photo_payload = payload.fetch("deliverables").find { |item| item.fetch("id") == photo_deliverable.id }
    expect(photo_payload.fetch("assets").sole).to include(
      "id" => photo_asset.id,
      "preview_path" => "/api/v1/media_assets/#{photo_asset.id}/preview",
      "download_path" => "/api/v1/media_assets/#{photo_asset.id}/download"
    )

    expect {
      post "/api/v1/portal/listings/#{listing.id}/deliverables/#{video_deliverable.id}/change_requests",
           params: { change_request: { body: "Please change the video." } }
    }.not_to change(Message, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to eq("change_requests_only_for_delivered_work")

    post "/api/v1/portal/listings/#{listing.id}/deliverables/#{photo_deliverable.id}/change_requests",
         params: {
           change_request: {
             body: "Please replace the front exterior photo.",
             media_asset_ids: [ photo_asset.id ]
           }
         }

    expect(response).to have_http_status(:created)
    expect(photo_deliverable.reload).to have_attributes(status: "in_progress", delivered_at: nil)
    change_request = response.parsed_body.fetch("change_request")
    expect(change_request.fetch("deliverable")).to include(
      "id" => photo_deliverable.id,
      "status" => "in_progress",
      "can_request_changes" => false
    )

    conversation = Conversation.find(change_request.fetch("conversation_id"))
    message = conversation.messages.sole
    expect(message).to have_attributes(
      message_kind: "change_request",
      listing_id: listing.id,
      order_deliverable_id: photo_deliverable.id
    )
    expect(message.message_media_references.pluck(:media_asset_id)).to eq([ photo_asset.id ])
    expect(Conversations::NotifyJob).to have_received(:perform_later).with(message.id)
  end
end
