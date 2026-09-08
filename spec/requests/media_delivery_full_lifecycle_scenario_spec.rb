require "rails_helper"
require "tempfile"

RSpec.describe "Media delivery full lifecycle API scenario", type: :request do
  include ActiveJob::TestHelper

  let!(:organization) { Organization.create!(name: "Full lifecycle agency", slug: "full-lifecycle-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Lifecycle manager", email: "full-lifecycle-manager@example.test",
                password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Lifecycle client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Lifecycle customer", email: "full-lifecycle-client@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "44 Lifecycle Avenue") }
  let!(:board) { organization.default_board }
  let!(:service) do
    organization.products.create!(slug: "full-lifecycle-photo", title: "Standard property photography",
                                  description: "A complete set of property photos.", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) do
    service.product_variants.create!(title: "Up to 1,000 sqft", price_cents: 30_000, sqft_min: 0, sqft_max: 1_000)
  end

  before do
    ActiveJob::Base.queue_adapter = :test
    organization.board_workflows.where(is_default: true).update_all(enabled: false)
    allow(Conversations::NotifyJob).to receive(:perform_later)
    allow(DeliveryStorage).to receive(:write)
    allow(DeliveryStorage).to receive(:exist?).and_return(true)
    sign_in manager
  end

  it "carries one purchased service from approval to staff media, portal delivery, and a change request" do
    post "/api/v1/boards/#{board.id}/workflows", params: {
      board_workflow: {
        name: "Lifecycle delivery automation",
        trigger_key: "order_approved",
        enabled: true,
        status_mappings_attributes: BoardWorkflow.default_status_mapping_attributes(board),
        actions_attributes: [
          { action_type: "create_or_group_child_task", configuration: { customer_visible: true }, position: 0 },
          { action_type: "place_on_board", configuration: { board_id: board.id, column_key: "todo" }, position: 1 }
        ]
      }
    }
    expect(response).to have_http_status(:created)

    post "/api/v1/orders", params: {
      order: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: variant.id, quantity: 1 } ]
      }
    }
    expect(response).to have_http_status(:created)
    order_id = response.parsed_body.dig("order", "id")

    perform_enqueued_jobs(only: BoardWorkflowJob) do
      post "/api/v1/orders/#{order_id}/approve"
    end
    expect(response).to have_http_status(:ok)

    order = Order.find(order_id)
    deliverable = order.order_deliverables.sole
    task = deliverable.workflow_tasks.sole
    expect(task).to have_attributes(status: "todo", customer_visible: true)
    expect(order.order_items.count).to eq(1)
    expect(order.total_cents).to eq(30_000)

    patch "/api/v1/workflow_tasks/#{task.id}", params: {
      workflow_task: { status: "done", position: 0 }
    }
    expect(response).to have_http_status(:ok)
    expect(deliverable.reload).to have_attributes(status: "delivered", delivered_at: be_present)

    upload = Tempfile.new([ "lifecycle-photo", ".jpg" ])
    upload.write("image bytes")
    upload.rewind
    post "/api/v1/media_assets/upload", params: {
      listing_id: listing.id,
      order_deliverable_id: deliverable.id,
      file: Rack::Test::UploadedFile.new(upload.path, "image/jpeg", true, original_filename: "front.jpg")
    }
    expect(response).to have_http_status(:created)
    asset = deliverable.media_assets.sole

    perform_enqueued_jobs(only: MediaAssets::VerifyUploadJob)
    expect(asset.reload).to be_ready

    sign_out manager
    sign_in client_user
    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    portal_deliverable = response.parsed_body.fetch("deliverables").sole
    expect(portal_deliverable).to include(
      "title" => "Standard property photography",
      "status" => "delivered",
      "asset_count" => 1,
      "can_request_changes" => true
    )
    expect(portal_deliverable.fetch("assets").sole).to include(
      "id" => asset.id,
      "preview_path" => "/api/v1/media_assets/#{asset.id}/preview",
      "download_path" => "/api/v1/media_assets/#{asset.id}/download"
    )
    expect(portal_deliverable.fetch("assets").sole.keys).not_to include("storage_key")

    post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
      change_request: {
        body: "Please replace the exterior photo.",
        media_asset_ids: [ asset.id ]
      }
    }

    expect(response).to have_http_status(:created)
    change_request = response.parsed_body.fetch("change_request")
    expect(deliverable.reload).to have_attributes(status: "in_progress", delivered_at: nil)
    expect(Conversations::NotifyJob).to have_received(:perform_later)

    conversation = Conversation.find(change_request.fetch("conversation_id"))
    get "/api/v1/conversations/#{conversation.id}"

    expect(response).to have_http_status(:ok)
    message = response.parsed_body.dig("conversation", "messages").sole
    expect(message).to include(
      "message_kind" => "change_request",
      "listing_id" => listing.id,
      "order_deliverable_id" => deliverable.id
    )
    expect(message.fetch("media_references")).to contain_exactly(
      hash_including("id" => asset.id, "preview_path" => "/api/v1/media_assets/#{asset.id}/preview")
    )
  ensure
    upload&.close!
  end

  it "does not let a customer use a delivered asset from another listing in a change request" do
    order = Order.create!(organization:, client_account:, listing:, payment_mode: :pay_later,
                          status: :approved, approved_at: Time.current)
    order_item = order.order_items.create!(product: service, product_variant: variant, title: service.title,
                                           quantity: 1, unit_price_cents: variant.price_cents,
                                           total_cents: variant.price_cents)
    deliverable = Orders::DeliverableMaterializer.new(order:).call.sole
    deliverable.update!(status: :delivered, delivered_at: Time.current)
    foreign_listing = Listing.create!(organization:, client_account:, address_line_1: "45 Foreign Avenue")
    foreign_order = Order.create!(organization:, client_account:, listing: foreign_listing, payment_mode: :pay_later,
                                  status: :approved, approved_at: Time.current)
    foreign_item = foreign_order.order_items.create!(product: service, product_variant: variant, title: service.title,
                                                     quantity: 1, unit_price_cents: variant.price_cents,
                                                     total_cents: variant.price_cents)
    foreign_deliverable = Orders::DeliverableMaterializer.new(order: foreign_order).call.sole
    foreign_deliverable.update!(status: :delivered, delivered_at: Time.current)
    foreign_asset = MediaAsset.create!(organization:, listing: foreign_listing, order: foreign_order,
                                       order_item: foreign_item, order_deliverable: foreign_deliverable, kind: :final,
                                       status: :ready, storage_key: "full-lifecycle/foreign.jpg",
                                       filename: "foreign.jpg", content_type: "image/jpeg", byte_size: 5,
                                       customer_visible: true)
    sign_out manager
    sign_in client_user

    expect {
      post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
        change_request: { body: "Use the other listing's file", media_asset_ids: [ foreign_asset.id ] }
      }
    }.not_to change(Message, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to eq("invalid_media_asset_reference")
    expect(deliverable.reload).to be_delivered
  end
end
