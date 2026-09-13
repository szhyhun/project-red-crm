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
  let!(:service) do
    organization.products.create!(slug: "portal-review-service", title: "Portal review service", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 30_000) }
  let!(:order) do
    Orders::Create.call(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).fetch(:order).tap { |record| record.update!(status: :approved, approved_at: Time.current) }
  end
  let!(:deliverable) { Orders::DeliverableMaterializer.new(order:).call.sole.tap { |record| record.update!(status: :delivered, delivered_at: Time.current) } }
  let!(:asset) do
    deliverable.media_assets.create!(organization:, listing:, order:, order_item: order.order_items.sole,
                                     kind: :final, status: :ready, category: :images,
                                     storage_key: "portal-review/front.jpg", filename: "front.jpg",
                                     content_type: "image/jpeg", byte_size: 5, customer_visible: true)
  end

  before { allow(Conversations::NotifyJob).to receive(:perform_later) }

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

  it "commits a legacy change request as one business action" do
    result = ClientPortal::CreateChangeRequest.call(
      listing:, deliverable:, actor: customer, body: "Replace the front photo", body_html: "<p>Replace the front photo</p>",
      assets: [ asset ], selected_ids: [ asset.id ]
    )

    expect(result).to be_success
    expect(result.fetch(:message)).to have_attributes(message_kind: "change_request", listing:, order_deliverable: deliverable)
    expect(result.fetch(:message).message_media_references.sole.media_asset).to eq(asset)
    expect(deliverable.reload).to be_in_progress
    expect(ActivityEvent.where(subject: deliverable, event_type: "order_deliverable.change_requested")).to exist
    expect(Conversations::NotifyJob).to have_received(:perform_later).with(result.fetch(:message).id)
  end

  it "returns a handled validation failure before creating a message" do
    result = ClientPortal::CreateChangeRequest.call(
      listing:, deliverable:, actor: customer, body: "", body_html: "", assets: [], selected_ids: []
    )

    expect(result).to be_failure
    expect(result.failure.code).to eq("message_required")
    expect(Message.where(order_deliverable: deliverable)).to be_empty
    expect(deliverable.reload).to be_delivered
  end
end
