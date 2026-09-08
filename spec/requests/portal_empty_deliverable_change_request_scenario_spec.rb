require "rails_helper"

RSpec.describe "Portal empty deliverable change request API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Empty deliverable agency", slug: "empty-deliverable-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Empty deliverable client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Empty deliverable customer", email: "empty-deliverable-client@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "18 Empty Deliverable Street") }
  let!(:service) do
    organization.products.create!(slug: "empty-deliverable-service", title: "Property photography",
                                  description: "The final property photo set.", kind: :service,
                                  deliverable_type: :photography, sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 25_000) }
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

  before do
    allow(Conversations::NotifyJob).to receive(:perform_later)
    sign_in client_user
  end

  it "shows a change-request action for delivered work with no visible files" do
    get "/api/v1/portal/listings/#{listing.id}/media"

    expect(response).to have_http_status(:ok)
    portal_deliverable = response.parsed_body.fetch("deliverables").sole
    expect(portal_deliverable).to include(
      "status" => "delivered",
      "asset_count" => 0,
      "assets" => [],
      "can_request_changes" => true
    )
  end

  it "opens a request from an empty delivered service without creating a media reference" do
    expect {
      post "/api/v1/portal/listings/#{listing.id}/deliverables/#{deliverable.id}/change_requests", params: {
        change_request: { body: "Please send the exterior photo set." }
      }
    }.to change(Message, :count).by(1)

    expect(response).to have_http_status(:created)
    payload = response.parsed_body.fetch("change_request")
    message = Message.find(payload.fetch("message_id"))

    expect(message).to have_attributes(
      author: client_user,
      body: "Please send the exterior photo set.",
      message_kind: "change_request",
      listing_id: listing.id,
      order_deliverable_id: deliverable.id
    )
    expect(message.message_media_references).to be_empty
    expect(deliverable.reload).to have_attributes(status: "in_progress", delivered_at: nil)
    expect(payload.dig("deliverable", "can_request_changes")).to be(false)
    expect(Conversations::NotifyJob).to have_received(:perform_later).with(message.id)
  end
end
