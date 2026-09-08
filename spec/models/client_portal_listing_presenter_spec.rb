require "rails_helper"

RSpec.describe ClientPortal::ListingPresenter, type: :model do
  let!(:organization) { Organization.create!(name: "Presenter agency", slug: "presenter-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Presenter client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "1 Presenter Street") }

  subject(:payload) { described_class.new(listing).to_h }

  it "starts a new listing in the customer request state" do
    expect(payload).to include(
      id: listing.id,
      status: "request_received",
      lifecycle_status: "request_received",
      lifecycle_label: "Request received"
    )
  end

  it "uses the customer-friendly lifecycle label for scheduled work" do
    Appointment.create!(organization:, listing:, starts_at: 2.days.from_now, ends_at: 2.days.from_now + 1.hour)

    expect(payload).to include(status: "scheduled", lifecycle_label: "Scheduled")
  end

  it "uses in progress for active production work and completed appointments" do
    listing.update!(status: :in_production)
    expect(payload).to include(status: "in_progress", lifecycle_label: "In progress")

    listing.update!(status: :booked)
    Appointment.create!(organization:, listing:, starts_at: 2.days.ago, ends_at: 2.days.ago + 1.hour,
                        status: :completed)

    expect(payload).to include(status: "in_progress", lifecycle_label: "In progress")
  end

  it "uses ready while the listing is in customer review" do
    listing.update!(status: :review)

    expect(payload).to include(status: "ready", lifecycle_label: "Ready for review")
  end

  it "uses delivered before the lower-priority workflow states" do
    listing.update!(status: :delivered, delivery_status: :delivered)

    expect(payload).to include(status: "delivered", lifecycle_label: "Delivered")
  end

  it "uses closed for a cancelled listing" do
    listing.update!(status: :cancelled)

    expect(payload).to include(status: "closed", lifecycle_label: "Closed")
  end

  it "does not expose the internal listing or organization associations" do
    expect(payload).not_to have_key(:client_account)
    expect(payload).not_to have_key(:organization)
  end
end
