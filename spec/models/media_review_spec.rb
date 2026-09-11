require "rails_helper"

RSpec.describe MediaReview, type: :model do
  let!(:organization) { Organization.create!(name: "Review model agency", slug: "review-model-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Review model client", kind: :agent) }
  let!(:customer) do
    User.create!(organization:, name: "Review model customer", email: "review-model-customer@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:manager) do
    User.create!(organization:, name: "Review model manager", email: "review-model-manager@example.test",
                password: "long-enough-password", role: :manager)
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "Review Model Street") }
  let!(:service) do
    organization.products.create!(slug: "review-model-service", title: "Review model photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 10_000) }
  let!(:order) { Order.create!(organization:, client_account:, listing:, status: :approved, approved_at: Time.current, payment_mode: :pay_later) }
  let!(:order_item) do
    order.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                              unit_price_cents: variant.price_cents, total_cents: variant.price_cents)
  end
  let!(:deliverable) do
    Orders::DeliverableMaterializer.new(order:).call.sole.tap do |record|
      record.update!(status: :delivered, delivered_at: Time.current, delivery_version: 2)
    end
  end
  let!(:asset) do
    deliverable.media_assets.create!(organization:, listing:, order:, order_item:, kind: :final, status: :ready,
                                     storage_key: "review-model/front.jpg", filename: "front.jpg",
                                     content_type: "image/jpeg", category: "images", customer_visible: true)
  end
  let!(:review) do
    MediaReview.create!(organization:, listing:, client_account:, created_by: customer, number: 1, delivery_version: 2)
  end
  let!(:review_deliverable) do
    review.media_review_deliverables.create!(order_deliverable: deliverable, delivery_version: 2, position: 0)
  end
  let!(:review_asset) do
    review.media_review_assets.create!(media_asset: asset, order_deliverable: deliverable, asset_version: asset.version,
                                       filename: asset.filename, content_type: asset.content_type, byte_size: asset.byte_size,
                                       position: 0)
  end

  it "allows a draft review to have no outcome until it is submitted" do
    expect(review).to be_valid
    expect(review).to be_open
    expect(review.outcome).to be_nil
  end

  it "rejects a comment region without all of its coordinates" do
    thread = review.media_review_threads.build(created_by: customer, media_review_asset: review_asset, anchor_type: :region,
                                               anchor_x: 10, anchor_y: 10, anchor_width: 20)

    expect(thread).not_to be_valid
    expect(thread.errors.full_messages).to include("region comments require x, y, width, and height")
  end

  it "rejects a review snapshot asset that is no longer customer-visible" do
    hidden = asset.dup
    hidden.storage_key = "review-model/hidden.jpg"
    hidden.filename = "hidden.jpg"
    hidden.customer_visible = false
    hidden.save!

    invalid = review.media_review_assets.build(media_asset: hidden, order_deliverable: deliverable,
                                               filename: hidden.filename, content_type: hidden.content_type)

    expect(invalid).not_to be_valid
    expect(invalid.errors.full_messages).to include("Media asset must be ready and customer-visible")
  end

  it "publishes draft comments and sanitizes a submitted review summary" do
    thread = review.media_review_threads.create!(created_by: customer, media_review_asset: review_asset)
    comment = thread.media_review_comments.create!(author: customer, body_html: "<p>Looks good</p><script>bad()</script>")

    review.submit!(outcome: "comment", submitted_by: customer,
                   summary_html: "<p>Approved note</p><script>bad()</script>")

    expect(review.reload).to have_attributes(status: "submitted", outcome: "comment", submitted_by_id: customer.id)
    expect(comment.reload).to be_published
    expect(review.summary).to eq("Approved note")
    expect(review.summary_html).to include("<p>Approved note</p>")
    expect(review.summary_html).not_to include("script")
    expect(ActivityEvent.where(subject: review, event_type: "media_review.comment")).to exist
  end

  it "reopens the included deliverable only for a request-changes outcome" do
    review.submit!(outcome: "request_changes", submitted_by: customer)

    expect(review.reload).to be_changes_requested
    expect(deliverable.reload).to have_attributes(status: "in_progress", delivered_at: nil)
    expect(ActivityEvent.where(subject: deliverable, event_type: "order_deliverable.change_requested")).to exist
  end

  it "can remove a deliverable without querying message references as a direct column" do
    expect { deliverable.destroy! }.not_to raise_error
    expect(OrderDeliverable.exists?(deliverable.id)).to be(false)
  end

  it "increments the delivery version when work is delivered again" do
    deliverable.update!(status: :in_progress, delivered_at: nil)
    deliverable.update!(status: :delivered, delivered_at: Time.current)

    expect(deliverable.reload.delivery_version).to eq(3)
  end
end
