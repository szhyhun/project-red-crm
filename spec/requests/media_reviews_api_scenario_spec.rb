require "rails_helper"

RSpec.describe "Media reviews API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Review agency", slug: "review-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Review manager", email: "review-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Review client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Review customer", email: "review-client@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:other_account) { ClientAccount.create!(organization:, name: "Other review client", kind: :agent) }
  let!(:other_user) do
    User.create!(organization:, name: "Other customer", email: "other-review-client@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: other_account, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "Review Avenue") }
  let!(:service) do
    Product.create!(organization:, slug: "review-photography", title: "Property photography", kind: :service,
                    deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Up to 2,000 sqft", price_cents: 29_900, sqft_min: 0, sqft_max: 2_000) }
  let!(:order) do
    Order.create!(organization:, client_account:, listing:, status: :approved, approved_at: Time.current,
                  payment_mode: :pay_later)
  end
  let!(:order_item) do
    order.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                              unit_price_cents: variant.price_cents, total_cents: variant.price_cents,
                              snapshot: OrderItem.catalog_snapshot(variant))
  end
  let!(:deliverable) do
    Orders::DeliverableMaterializer.new(order:).call.sole.tap do |record|
      record.update!(status: :delivered, delivered_at: Time.current, delivery_version: 3)
    end
  end
  let!(:asset) do
    deliverable.media_assets.create!(organization:, listing:, order:, order_item:, kind: :final, status: :ready,
                                     storage_key: "reviews/#{listing.id}/front.jpg", filename: "front.jpg",
                                     content_type: "image/jpeg", byte_size: 12, category: "images",
                                     customer_visible: true)
  end

  before do
    allow(Conversations::NotifyJob).to receive(:perform_later)
  end

  it "keeps another customer from reading or creating a review for this listing" do
    sign_in client_user
    post "/api/v1/portal/listings/#{listing.id}/reviews"
    review = MediaReview.order(:id).last

    sign_out client_user
    sign_in other_user

    get "/api/v1/portal/reviews/#{review.id}"
    expect(response).to have_http_status(:not_found)

    post "/api/v1/portal/listings/#{listing.id}/reviews"
    expect(response).to have_http_status(:not_found)
    expect(MediaReview.count).to eq(1)
  end

  it "creates one review draft and snapshots only the delivered customer-visible assets" do
    deliverable.media_assets.create!(organization:, listing:, order:, order_item:, kind: :final, status: :processing,
                                     storage_key: "reviews/#{listing.id}/processing.jpg", filename: "processing.jpg",
                                     content_type: "image/jpeg", byte_size: 10, category: "images",
                                     customer_visible: true)
    deliverable.media_assets.create!(organization:, listing:, order:, order_item:, kind: :final, status: :ready,
                                     storage_key: "reviews/#{listing.id}/hidden.jpg", filename: "hidden.jpg",
                                     content_type: "image/jpeg", byte_size: 10, category: "images",
                                     customer_visible: false)

    sign_in client_user

    expect {
      post "/api/v1/portal/listings/#{listing.id}/reviews"
    }.to change(MediaReview, :count).by(1)
      .and change(MediaReviewDeliverable, :count).by(1)
      .and change(MediaReviewAsset, :count).by(1)


    expect(response).to have_http_status(:created)
    review = MediaReview.order(:id).last
    expect(review).to have_attributes(status: "open", outcome: nil, delivery_version: 3, created_by_id: client_user.id)
    payload = response.parsed_body.fetch("media_review")
    expect(payload).to include("number" => 1, "status" => "open", "can_submit" => true, "pending_comment_count" => 0)
    expect(payload.dig("deliverables", 0)).to include("title" => deliverable.title, "asset_count" => 1)
    expect(payload.dig("deliverables", 0, "assets", 0)).to include(
      "media_asset_id" => asset.id,
      "filename" => "front.jpg",
      "preview_path" => "/api/v1/media_assets/#{asset.id}/preview"
    )
    expect(payload.dig("deliverables", 0, "assets", 0)).not_to have_key("storage_key")

    post "/api/v1/portal/listings/#{listing.id}/reviews"
    expect(response).to have_http_status(:ok)
    expect(MediaReview.count).to eq(1)
    expect(response.parsed_body.dig("media_review", "id")).to eq(review.id)
  end

  it "keeps an unsubmitted review comment private and anchors it to the selected asset" do
    sign_in client_user
    post "/api/v1/portal/listings/#{listing.id}/reviews"
    review = MediaReview.order(:id).last
    review_asset = review.media_review_assets.sole

    expect {
      post "/api/v1/portal/reviews/#{review.id}/threads", params: {
        thread: { media_review_asset_id: review_asset.id, anchor_type: "region", anchor_x: 12.5,
                  anchor_y: 24.0, anchor_width: 18.0, anchor_height: 10.0 },
        comment: { body_html: "<p>Please brighten this room.</p>" }
      }
    }.to change(MediaReviewThread, :count).by(1).and change(MediaReviewComment, :count).by(1)

    expect(response).to have_http_status(:created)
    thread = review.media_review_threads.sole
    expect(thread).to have_attributes(anchor_type: "region", media_review_asset_id: review_asset.id)
    expect(thread.media_review_comments.sole).to have_attributes(status: "draft", body: "Please brighten this room.")
    expect(response.parsed_body.dig("media_review", "threads", 0, "comments", 0, "status")).to eq("draft")

    sign_out client_user
    sign_in manager
    get "/api/v1/media_reviews/#{review.id}"
    expect(response).to have_http_status(:ok)
    # The thread is still only the customer's draft, so staff do not see it at all.
    expect(response.parsed_body.dig("media_review", "threads")).to be_empty
  end

  it "publishes an explicit approval without changing the delivered state" do
    sign_in client_user
    post "/api/v1/portal/listings/#{listing.id}/reviews"
    review = MediaReview.order(:id).last
    review_asset = review.media_review_assets.sole
    post "/api/v1/portal/reviews/#{review.id}/threads", params: {
      thread: { media_review_asset_id: review_asset.id },
      comment: { body: "Looks good." }
    }

    post "/api/v1/portal/reviews/#{review.id}/submit", params: {
      media_review: { outcome: "approve", summary: "Approved for delivery." }
    }

    expect(response).to have_http_status(:ok)
    expect(review.reload).to have_attributes(status: "approved", outcome: "approve", submitted_by_id: client_user.id)
    expect(deliverable.reload).to be_delivered
    expect(review.media_review_comments.sole).to be_published
    expect(Message.where(media_review: review)).to exist
    expect(Conversations::NotifyJob).to have_received(:perform_later)
  end

  it "moves only the reviewed deliverables back to work and notifies the account conversation" do
    sign_in client_user
    post "/api/v1/portal/listings/#{listing.id}/reviews"
    review = MediaReview.order(:id).last

    post "/api/v1/portal/reviews/#{review.id}/submit", params: {
      media_review: { outcome: "request_changes", summary_html: "<p>Rework the delivery.</p>" }
    }

    expect(response).to have_http_status(:ok)
    expect(review.reload).to have_attributes(status: "changes_requested", outcome: "request_changes")
    expect(deliverable.reload).to have_attributes(status: "in_progress", delivered_at: nil)
    message = Message.where(media_review: review).sole
    expect(message).to have_attributes(message_kind: "review_notification", listing_id: listing.id, media_review_id: review.id)
    expect(message.body).to include("Request changes")
    get "/api/v1/conversations/#{message.conversation_id}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("conversation", "messages").sole.dig("context", "review")).to include(
      "id" => review.id, "number" => review.number, "status" => "changes_requested", "outcome" => "request_changes"
    )
    expect(ActivityEvent.where(subject: review, event_type: "media_review.request_changes")).to exist
    expect(Conversations::NotifyJob).to have_received(:perform_later).with(message.id)
  end

  it "treats a listing with no review record as implicitly accepted" do
    sign_in client_user
    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("review" => nil, "review_state" => "implicitly_accepted")
    expect(MediaReview.count).to eq(0)
  end

  it "opens a review for ready customer-visible listing media without an order deliverable" do
    legacy_listing = Listing.create!(organization:, client_account:, address_line_1: "Unbundled Media Way")
    legacy_asset = legacy_listing.media_assets.create!(
      organization:, listing: legacy_listing, kind: :final, status: :ready,
      storage_key: "reviews/#{legacy_listing.id}/unbundled.jpg", filename: "unbundled.jpg",
      content_type: "image/jpeg", byte_size: 12, category: "images", customer_visible: true
    )

    sign_in client_user

    expect {
      post "/api/v1/portal/listings/#{legacy_listing.id}/reviews"
    }.to change(MediaReview, :count).by(1).and change(MediaReviewAsset, :count).by(1)

    expect(response).to have_http_status(:created)
    review = MediaReview.order(:id).last
    expect(review.media_review_deliverables).to be_empty
    expect(response.parsed_body.dig("media_review", "asset_groups", 0)).to include(
      "title" => "Property photos", "asset_count" => 1
    )
    expect(response.parsed_body.dig("media_review", "asset_groups", 0, "assets", 0)).to include(
      "media_asset_id" => legacy_asset.id, "filename" => "unbundled.jpg"
    )
  end

  it "rejects a deliverable or asset from outside the review snapshot" do
    sign_in client_user
    post "/api/v1/portal/listings/#{listing.id}/reviews"
    review = MediaReview.order(:id).last
    late_asset = deliverable.media_assets.create!(organization:, listing:, order:, order_item:, kind: :final, status: :ready,
                                                   storage_key: "reviews/#{listing.id}/late.jpg", filename: "late.jpg",
                                                   content_type: "image/jpeg", category: "images", customer_visible: true)

    post "/api/v1/portal/reviews/#{review.id}/threads", params: {
      thread: { media_review_asset_id: late_asset.id },
      comment: { body: "Wrong snapshot." }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to eq("invalid_review_asset_reference")
    expect(review.media_review_threads).to be_empty
  end

  it "lets staff reply to and resolve a review thread without exposing draft comments" do
    sign_in client_user
    post "/api/v1/portal/listings/#{listing.id}/reviews"
    review = MediaReview.order(:id).last
    review_asset = review.media_review_assets.sole
    post "/api/v1/portal/reviews/#{review.id}/threads", params: {
      thread: { media_review_asset_id: review_asset.id },
      comment: { body: "Please fix the color." }
    }
    thread = review.media_review_threads.sole
    post "/api/v1/portal/reviews/#{review.id}/submit", params: { media_review: { outcome: "request_changes" } }

    sign_out client_user
    sign_in manager
    post "/api/v1/media_review_threads/#{thread.id}/comments", params: { comment: { body: "Queued for the editor." } }
    expect(response).to have_http_status(:created)
    expect(thread.media_review_comments.where(status: :published).count).to eq(2)

    post "/api/v1/media_review_threads/#{thread.id}/resolve"
    expect(response).to have_http_status(:ok)
    expect(thread.reload).to have_attributes(status: "resolved", resolved_by_id: manager.id)
  end
end
