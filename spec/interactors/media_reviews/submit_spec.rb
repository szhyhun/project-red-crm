require "rails_helper"

RSpec.describe MediaReviews::Submit, type: :interactor do
  let!(:organization) { Organization.create!(name: "Submit review agency", slug: "submit-review-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Submit review client", kind: :agent) }
  let!(:customer) do
    User.create!(organization:, name: "Submit review customer", email: "submit-review@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "Submit Review Street") }
  let!(:review) do
    MediaReview.create!(organization:, listing:, client_account:, created_by: customer, number: 1, delivery_version: 1)
  end

  before do
    allow(Conversations::NotifyJob).to receive(:perform_later)
  end

  it "submits the review and publishes a notification in the account conversation" do
    result = described_class.call(review:, outcome: "approve", submitted_by: customer)

    expect(result).to be_success
    expect(result.fetch(:review)).to have_attributes(status: "approved", outcome: "approve", submitted_by: customer)
    expect(review.reload.activity_events.where(event_type: "media_review.approve")).to exist
    message = review.messages.sole
    expect(message).to have_attributes(message_kind: "review_notification", media_review: review)
    expect(Conversations::NotifyJob).to have_received(:perform_later).with(message.id)
  end

  it "rejects a request for changes without a summary or comment" do
    result = described_class.call(review:, outcome: "request_changes", submitted_by: customer)

    expect(result).to be_failure
    expect(result.failure.code).to eq("media_review_submit_invalid")
    expect(review.reload).to be_open
    expect(review.messages).to be_empty
  end

  it "does not submit the same review twice" do
    expect(described_class.call(review:, outcome: "comment", submitted_by: customer)).to be_success

    result = described_class.call(review:, outcome: "approve", submitted_by: customer)

    expect(result).to be_failure
    expect(result.failure.code).to eq("media_review_submit_invalid")
    expect(review.reload).to have_attributes(status: "submitted", outcome: "comment")
    expect(review.messages.count).to eq(1)
  end
end
