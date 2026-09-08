require "rails_helper"

RSpec.describe "Portal change request notification failure scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Notification failure agency", slug: "notification-failure-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Notification failure client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Notification failure customer", email: "notification-failure@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "2 Notification Failure Street") }
  let!(:service) do
    organization.products.create!(slug: "notification-failure-service", title: "Notification failure photography",
                                  kind: :service, deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }
  let!(:order) do
    Orders::Creator.new(organization:, attributes: {
      client_account_id: client_account.id, listing_id: listing.id, payment_mode: "pay_later",
      items: [ { product_variant_id: variant.id, quantity: 1 } ]
    }).create!.tap do |record|
      record.update!(status: :approved, approved_at: Time.current)
    end
  end
  let!(:deliverable) do
    Orders::DeliverableMaterializer.new(order:).call.sole.tap do |record|
      record.update!(status: :delivered, delivered_at: Time.current)
    end
  end

  before { sign_in client_user }

  it "returns success after the message commits when notification scheduling is unavailable" do
    allow(Conversations::NotifyJob).to receive(:perform_later)
      .and_raise(Redis::CannotConnectError, "redis unavailable")

    expect {
      post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
        change_request: { body: "Please replace the exterior photo." }
      }
    }.to change(Message, :count).by(1)

    expect(response).to have_http_status(:created)
    message = Message.find(response.parsed_body.dig("change_request", "message_id"))
    expect(message).to have_attributes(message_kind: "change_request", order_deliverable: deliverable,
                                       listing:, body: "Please replace the exterior photo.")
    expect(deliverable.reload).to have_attributes(status: "in_progress", delivered_at: nil)
    expect(Conversations::NotifyJob).to have_received(:perform_later).with(message.id)
  end
end
