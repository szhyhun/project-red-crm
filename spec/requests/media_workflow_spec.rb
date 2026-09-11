require "rails_helper"

RSpec.describe "Media workflow API", type: :request do
  let!(:organization) { Organization.create!(name: "Portal Agency", slug: "portal-workflow") }
  let!(:other_organization) { Organization.create!(name: "Other Agency", slug: "other-workflow") }
  let!(:manager) do
    User.create!(organization:, name: "Morgan Manager", email: "workflow-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Avery Client", email: "workflow-client@example.test",
                 password: "long-enough-password", role: :client_admin)
  end
  let!(:other_client_account) { ClientAccount.create!(organization:, name: "Other Agent", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "111 Oak Bay Avenue") }
  let!(:other_listing) { Listing.create!(organization:, client_account: other_client_account, address_line_1: "Hidden Street") }
  let!(:service) do
    Product.create!(organization:, slug: "workflow-photos", title: "Property photography", kind: :service,
                    deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 29_900) }
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
    Orders::Approval.new(order:, actor: manager).call
    order.reload.order_deliverables.sole
  end

  before do
    ClientMembership.create!(client_account:, user: client_user, role: :admin)
  end

  it "returns customer-safe deliverables and API-relative private media paths" do
    asset = deliverable.media_assets.create!(organization:, listing:, kind: :final, status: :ready,
                                              storage_key: "organizations/#{organization.id}/deliverables/front.jpg",
                                              filename: "front.jpg", content_type: "image/jpeg", byte_size: 5,
                                              customer_visible: true)
    deliverable.update!(status: :delivered, delivered_at: Time.current)
    allow(DeliveryStorage).to receive(:public_url).with(asset.storage_key)
      .and_return("https://media.example.test/organizations/#{organization.id}/deliverables/front.jpg")

    sign_in client_user
    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload.dig("summary", "delivered_count")).to eq(1)
    serialized = payload.fetch("deliverables").sole
    expect(serialized).to include("status" => "delivered", "can_request_changes" => true, "asset_count" => 1)
    expect(serialized.dig("assets", 0)).to include(
      "id" => asset.id,
      "cdn_url" => "https://media.example.test/organizations/#{organization.id}/deliverables/front.jpg",
      "preview_path" => "/api/v1/media_assets/#{asset.id}/preview",
      "download_path" => "/api/v1/media_assets/#{asset.id}/download"
    )
    expect(serialized.dig("assets", 0)).not_to have_key("storage_key")
  end

  it "keeps a customer from reading another account's listing" do
    sign_in client_user

    get "/api/v1/portal/listings/#{other_listing.id}/media"

    expect(response).to have_http_status(:not_found)
  end

  it "returns ready listing media when an imported listing has no deliverables yet" do
    imported_listing = Listing.create!(organization:, client_account:, address_line_1: "Imported Media Street")
    assets = [
      imported_listing.media_assets.create!(organization:, kind: :final, status: :ready,
                                            storage_key: "organizations/#{organization.id}/imported/front.jpg",
                                            filename: "front.jpg", content_type: "image/jpeg", category: "images",
                                            byte_size: 5, customer_visible: true),
      imported_listing.media_assets.create!(organization:, kind: :final, status: :ready,
                                            storage_key: "organizations/#{organization.id}/imported/walkthrough.mp4",
                                            filename: "walkthrough.mp4", content_type: "video/mp4", category: "videos",
                                            byte_size: 7, customer_visible: true),
      imported_listing.media_assets.create!(organization:, kind: :final, status: :ready,
                                            storage_key: "organizations/#{organization.id}/imported/floor-plan.pdf",
                                            filename: "floor-plan.pdf", content_type: "application/pdf",
                                            category: "floor_plans", byte_size: 9, customer_visible: true)
    ]

    sign_in client_user
    get "/api/v1/portal/listings/#{imported_listing.id}/media"

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload.fetch("summary")).to include("deliverable_count" => 0, "delivered_count" => 0, "asset_count" => 3)
    expect(payload.fetch("deliverables")).to be_empty
    expect(payload.fetch("listing_asset_groups")).to contain_exactly(
      hash_including("key" => "images", "title" => "Property photos", "deliverable_type" => "photography",
                     "asset_count" => 1, "can_request_changes" => false),
      hash_including("key" => "videos", "title" => "Videos", "deliverable_type" => "video",
                     "asset_count" => 1, "can_request_changes" => false),
      hash_including("key" => "floor_plans", "title" => "Floor plans", "deliverable_type" => "floor_plan",
                     "asset_count" => 1, "can_request_changes" => false)
    )
    expect(payload.fetch("listing_asset_groups").flat_map { |group| group.fetch("assets") }.map { |asset| asset.fetch("id") })
      .to contain_exactly(*assets.map(&:id))
    expect(payload.fetch("listing_assets").map { |asset| asset.fetch("id") }).to contain_exactly(*assets.map(&:id))
    expect(payload.fetch("listing_assets").map { |asset| asset.fetch("category") }).to contain_exactly("images", "videos", "floor_plans")
    expect(payload.fetch("listing_assets")).to all(satisfy { |asset| !asset.key?("storage_key") })
  end

  it "keeps each ordered service in its own portal deliverable card" do
    photo_asset = deliverable.media_assets.create!(organization:, listing:, kind: :final, status: :ready,
                                                    storage_key: "organizations/#{organization.id}/deliverables/ordered-photo.jpg",
                                                    filename: "ordered-photo.jpg", content_type: "image/jpeg",
                                                    category: "images", byte_size: 5, customer_visible: true)
    deliverable.update!(status: :delivered, delivered_at: Time.current)

    video = Product.create!(organization:, slug: "workflow-videos", title: "Property video", kind: :service,
                            deliverable_type: "video", sla_days: 3)
    video_variant = video.product_variants.create!(title: "Standard", price_cents: 35_000)
    video_order = Orders::Creator.new(
      organization:,
      attributes: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: video_variant.id, quantity: 1 } ]
      }
    ).create!
    video_order.update!(status: :approved, approved_at: Time.current)
    video_deliverable = Orders::DeliverableMaterializer.new(order: video_order).call.sole
    video_asset = video_deliverable.media_assets.create!(organization:, listing:, kind: :final, status: :ready,
                                                         storage_key: "organizations/#{organization.id}/deliverables/ordered-video.mp4",
                                                         filename: "ordered-video.mp4", content_type: "video/mp4",
                                                         category: "videos", byte_size: 7, customer_visible: true)
    video_deliverable.update!(status: :delivered, delivered_at: Time.current)

    sign_in client_user
    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    serialized = response.parsed_body.fetch("deliverables")
    expect(serialized.map { |item| item.fetch("title") }).to contain_exactly("Property photography", "Property video")
    expect(serialized.find { |item| item.fetch("id") == deliverable.id }).to include(
      "deliverable_type" => "photography", "asset_count" => 1
    )
    expect(serialized.find { |item| item.fetch("id") == video_deliverable.id }).to include(
      "deliverable_type" => "video", "asset_count" => 1
    )
    expect(serialized.flat_map { |item| item.fetch("assets") }.map { |asset| asset.fetch("id") })
      .to contain_exactly(photo_asset.id, video_asset.id)
    expect(response.parsed_body.fetch("listing_asset_groups")).to be_empty
  end

  it "creates an account conversation change request and returns the deliverable to work" do
    asset = deliverable.media_assets.create!(organization:, listing:, kind: :final, status: :ready,
                                              storage_key: "organizations/#{organization.id}/deliverables/request.jpg",
                                              filename: "request.jpg", content_type: "image/jpeg", byte_size: 5,
                                              customer_visible: true)
    deliverable.update!(status: :delivered, delivered_at: Time.current)

    sign_in client_user
    expect {
      post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
        change_request: {
          body_html: "<p>Please replace this photo.</p>",
          media_asset_ids: [ asset.id ]
        }
      }
    }.to change(Message, :count).by(1).and change(MessageMediaReference, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(deliverable.reload).to be_in_progress
    expect(response.parsed_body.dig("change_request", "deliverable", "status")).to eq("in_progress")
    message = Message.order(:id).last
    expect(message).to have_attributes(message_kind: "change_request", listing_id: listing.id, order_deliverable_id: deliverable.id)
    expect(message.referenced_media_assets).to contain_exactly(asset)
  end

  it "lets a permitted conversation reference existing media without copying it" do
    asset = deliverable.media_assets.create!(organization:, listing:, kind: :final, status: :ready,
                                              storage_key: "organizations/#{organization.id}/deliverables/chat-context.jpg",
                                              filename: "chat-context.jpg", content_type: "image/jpeg", byte_size: 5,
                                              customer_visible: true)
    conversation = Conversation.account_thread_for(organization:, client_account:)
    conversation.conversation_memberships.create!(user: client_user, role: :participant)

    sign_in client_user
    post "/api/v1/conversations/#{conversation.id}/messages", params: {
      message: { body: "Here is the photo", listing_id: listing.id, order_deliverable_id: deliverable.id,
                  media_asset_ids: [ asset.id ] }
    }

    expect(response).to have_http_status(:created)
    reference = response.parsed_body.dig("message", "media_references").sole
    expect(reference).to include(
      "id" => asset.id,
      "preview_path" => "/api/v1/media_assets/#{asset.id}/preview",
      "download_path" => "/api/v1/media_assets/#{asset.id}/download"
    )
    expect(reference).not_to have_key("storage_key")
    expect(MessageMediaReference.where(message: Message.order(:id).last, media_asset: asset)).to exist
  end

  it "rejects a selected asset that belongs to a different deliverable" do
    another_service = Product.create!(organization:, slug: "workflow-video", title: "Video", kind: :service,
                                      deliverable_type: "video")
    another_variant = another_service.product_variants.create!(title: "Standard", price_cents: 10_000)
    another_order = Orders::Creator.new(
      organization:,
      attributes: {
        client_account_id: client_account.id,
        listing_id: listing.id,
        payment_mode: "pay_later",
        items: [ { product_variant_id: another_variant.id, quantity: 1 } ]
      }
    ).create!
    another_deliverable = Orders::Approval.new(order: another_order, actor: manager).call.order_deliverables.sole
    asset = another_deliverable.media_assets.create!(organization:, listing:, kind: :final, status: :ready,
                                                      storage_key: "organizations/#{organization.id}/deliverables/foreign.jpg",
                                                      filename: "foreign.jpg", content_type: "image/jpeg", byte_size: 5,
                                                      customer_visible: true)
    deliverable.update!(status: :delivered, delivered_at: Time.current)

    sign_in client_user
    post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
      change_request: { body: "Wrong asset", media_asset_ids: [ asset.id ] }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to eq("invalid_media_asset_reference")
  end

  it "rejects workflow configuration from a non-manager and scopes another organization out" do
    other_board = other_organization.default_board
    sign_in client_user
    get "/api/v1/boards/#{other_board.id}/workflows"
    expect(response).to have_http_status(:not_found)

    sign_in client_user
    patch "/api/v1/order_deliverables/#{deliverable.id}", params: { order_deliverable: { status: "delivered" } }
    expect(response).to have_http_status(:forbidden)
  end
end
