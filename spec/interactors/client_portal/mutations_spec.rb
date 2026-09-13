require "rails_helper"

RSpec.describe "Client portal mutation interactors", type: :interactor do
  let!(:organization) { Organization.create!(name: "Portal action agency", slug: "portal-action-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Portal action client", kind: :agent) }
  let!(:customer) do
    User.create!(organization:, name: "Portal action customer", email: "portal-action@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin, status: :active)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "Portal Action Street") }
  let!(:appointment) do
    Appointment.create!(organization:, listing:, starts_at: 2.days.from_now, ends_at: 2.days.from_now + 1.hour,
                        status: :scheduled)
  end

  it "creates a draft listing and records the booking activity" do
    result = ClientPortal::CreateListing.call(
      organization:, client_account:, actor: customer, attributes: { address_line_1: "New Booking Street" }
    )

    expect(result).to be_success
    created = result.fetch(:listing)
    expect(created).to have_attributes(client_account:, status: "draft", delivery_status: "undelivered")
    expect(ActivityEvent.where(subject: created, event_type: "listing.booking_requested")).to exist
  end

  it "records a reschedule request and its listing activity atomically" do
    starts_at = 3.days.from_now.change(sec: 0)
    ends_at = starts_at + 1.hour

    result = ClientPortal::RequestReschedule.call(
      appointment:, actor: customer, starts_at:, ends_at:, notes: "After lunch"
    )

    expect(result).to be_success
    expect(result.fetch(:appointment).reload).to be_requested
    expect(appointment.appointment_events.where(event_type: "customer_reschedule_requested").sole.changeset).to include(
      "starts_at" => starts_at.iso8601,
      "ends_at" => ends_at.iso8601,
      "notes" => "After lunch"
    )
    expect(ActivityEvent.where(subject: listing, event_type: "appointment.customer_reschedule_requested")).to exist
  end
end
