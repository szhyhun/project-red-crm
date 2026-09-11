require "rails_helper"

RSpec.describe "Media review workspace", type: :request do
  let!(:organization) { Organization.create!(name: "Workspace agency", slug: "workspace-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Workspace manager", email: "workspace-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Workspace client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Workspace customer", email: "workspace-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:other_user) do
    other_account = ClientAccount.create!(organization:, name: "Other workspace client", kind: :agent)
    User.create!(organization:, name: "Other workspace customer", email: "other-workspace-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: other_account, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "Workspace Street") }
  let!(:service) do
    Product.create!(organization:, slug: "workspace-photography", title: "Property photography", kind: :service,
                    deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 29_900) }
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
      record.update!(status: :delivered, delivered_at: Time.current)
    end
  end
  let!(:asset) do
    deliverable.media_assets.create!(organization:, listing:, order:, order_item:, kind: :final, status: :ready,
                                     storage_key: "workspace/#{listing.id}/front.jpg", filename: "front.jpg",
                                     content_type: "image/jpeg", byte_size: 12, category: "images",
                                     customer_visible: true)
  end

  before do
    allow(Conversations::NotifyJob).to receive(:perform_later)
  end

  def open_draft_with_comment(body = "Please brighten the sky.")
    post "/api/v1/portal/listings/#{listing.id}/reviews"
    review = MediaReview.order(:id).last
    post "/api/v1/portal/reviews/#{review.id}/threads", params: {
      thread: { media_asset_id: asset.id },
      comment: { body: }
    }
    expect(response).to have_http_status(:created)
    review
  end

  def submit(review, outcome, **attributes)
    post "/api/v1/portal/reviews/#{review.id}/submit", params: { media_review: { outcome:, **attributes } }
  end

  def switch_to(user)
    sign_out :user
    sign_in user
  end

  it "does not show one customer the review page of another customer's listing" do
    sign_in other_user
    get "/api/v1/portal/listings/#{listing.id}/reviews"

    expect(response).to have_http_status(:not_found)
  end

  it "keeps a draft thread from staff, then lets both sides answer once it is submitted" do
    sign_in client_user
    review = open_draft_with_comment
    thread = review.media_review_threads.sole

    switch_to(manager)
    get "/api/v1/listings/#{listing.id}/media_reviews"
    expect(response.parsed_body.dig("workspace", "threads")).to be_empty
    expect(response.parsed_body.dig("workspace", "reviews")).to be_empty
    post "/api/v1/media_review_threads/#{thread.id}/comments", params: { comment: { body: "Too early to see this." } }
    expect(response).to have_http_status(:forbidden)

    switch_to(client_user)
    submit(review, "comment")
    expect(response).to have_http_status(:ok)

    switch_to(manager)
    post "/api/v1/media_review_threads/#{thread.id}/comments", params: { comment: { body: "Sky replaced." } }
    expect(response).to have_http_status(:created)

    switch_to(client_user)
    post "/api/v1/portal/review_threads/#{thread.id}/comments", params: { comment: { body: "Looks right now." } }
    expect(response).to have_http_status(:created)

    expect(thread.media_review_comments.order(:id).map(&:status)).to eq(%w[published published published])
    get "/api/v1/portal/listings/#{listing.id}/reviews"
    workspace_thread = response.parsed_body.dig("workspace", "threads").sole
    expect(workspace_thread.fetch("comments").map { |comment| comment.dig("author", "side") }).to eq(%w[customer staff customer])
    expect(workspace_thread.fetch("capabilities")).to include("update", "manage")
  end

  it "lets the customer resolve a submitted thread but not a customer of another account" do
    sign_in client_user
    review = open_draft_with_comment
    thread = review.media_review_threads.sole
    submit(review, "comment")

    switch_to(other_user)
    post "/api/v1/portal/review_threads/#{thread.id}/resolve"
    expect(response).to have_http_status(:not_found)
    expect(thread.reload).to be_open

    switch_to(client_user)
    post "/api/v1/portal/review_threads/#{thread.id}/resolve"
    expect(response).to have_http_status(:ok)
    expect(thread.reload).to have_attributes(status: "resolved", resolved_by_id: client_user.id)
  end

  it "refuses to send work back to production without saying what should change" do
    sign_in client_user
    post "/api/v1/portal/listings/#{listing.id}/reviews"
    review = MediaReview.order(:id).last

    submit(review, "request_changes")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "base")).to include("Add a comment or a summary that says what should change")
    expect(review.reload).to be_open
    expect(deliverable.reload).to be_delivered
  end

  it "refuses a second submission of the same review" do
    sign_in client_user
    review = open_draft_with_comment
    submit(review, "comment")
    expect(response).to have_http_status(:ok)

    submit(review, "request_changes", summary: "Changed my mind.")

    expect(response).to have_http_status(:forbidden)
    expect(review.reload).to have_attributes(status: "submitted", outcome: "comment")
    expect(deliverable.reload).to be_delivered
    expect(Message.where(media_review: review).count).to eq(1)
  end

  it "retires a draft once its service is delivered again and starts a new one" do
    sign_in client_user
    review = open_draft_with_comment

    deliverable.update!(status: :in_progress, delivered_at: nil)
    deliverable.update!(status: :delivered, delivered_at: Time.current)

    expect(review.reload).to be_outdated
    post "/api/v1/portal/listings/#{listing.id}/reviews"
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig("media_review", "id")).not_to eq(review.id)
  end

  it "removes a thread when its only draft comment is deleted" do
    sign_in client_user
    review = open_draft_with_comment
    comment = review.media_review_comments.sole

    delete "/api/v1/portal/review_comments/#{comment.id}"

    expect(response).to have_http_status(:no_content)
    expect(review.media_review_threads.reload).to be_empty
  end

  it "keeps a thread on a replaced file, marked as written against the earlier version" do
    sign_in client_user
    review = open_draft_with_comment
    submit(review, "request_changes")
    replacement = deliverable.media_assets.create!(organization:, listing:, order:, order_item:, kind: :final, status: :ready,
                                                   storage_key: "workspace/#{listing.id}/front-v2.jpg", filename: "front-v2.jpg",
                                                   content_type: "image/jpeg", byte_size: 14, category: "images",
                                                   customer_visible: true, version: 2)
    asset.update!(superseded_by: replacement)
    deliverable.update!(status: :delivered, delivered_at: Time.current)

    get "/api/v1/portal/listings/#{listing.id}/reviews"

    workspace = response.parsed_body.fetch("workspace")
    expect(workspace.dig("deliverables", 0, "assets").map { |file| file.fetch("id") }).to eq([ replacement.id ])
    expect(workspace.fetch("threads").sole).to include(
      "media_asset_id" => replacement.id, "original_media_asset_id" => asset.id,
      "outdated" => true, "file_available" => true
    )
  end

  it "takes a comment on a delivered service that has no files yet" do
    asset.update!(customer_visible: false)
    sign_in client_user
    post "/api/v1/portal/listings/#{listing.id}/reviews"
    review = MediaReview.order(:id).last

    post "/api/v1/portal/reviews/#{review.id}/threads", params: {
      thread: { order_deliverable_id: deliverable.id, anchor_type: "deliverable" },
      comment: { body: "The twilight photos are missing." }
    }

    expect(response).to have_http_status(:created)
    get "/api/v1/portal/listings/#{listing.id}/reviews"
    expect(response.parsed_body.dig("workspace", "threads").sole).to include(
      "anchor_type" => "deliverable", "order_deliverable_id" => deliverable.id, "pending" => true
    )
  end

  it "allows only one open draft per listing and customer account" do
    MediaReview.create!(organization:, listing:, client_account:, created_by: client_user, number: 1)

    expect {
      MediaReview.create!(organization:, listing:, client_account:, created_by: client_user, number: 2)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
