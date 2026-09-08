require "rails_helper"

RSpec.describe "Order integrity API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Order integrity agency", slug: "order-integrity-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Order integrity manager", email: "order-integrity-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Order integrity client", kind: :agent) }
  let!(:other_client_account) { ClientAccount.create!(organization:, name: "Other order client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "31 Integrity Street") }
  let!(:other_listing) { Listing.create!(organization:, client_account: other_client_account, address_line_1: "32 Integrity Street") }
  let!(:service) do
    organization.products.create!(slug: "integrity-photography", title: "Integrity photography", kind: :service,
                                  deliverable_type: "photography", sla_days: 2)
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 18_000) }

  before { sign_in manager }

  it "rejects an order whose listing belongs to a different customer account" do
    expect {
      post "/api/v1/orders", params: {
        order: {
          client_account_id: client_account.id,
          listing_id: other_listing.id,
          payment_mode: "pay_later",
          items: [ { product_variant_id: variant.id, quantity: 1 } ]
        }
      }
    }.not_to change(Order, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "listing")).to include("must belong to the selected customer account")
  end

  it "rolls back every order line when a later line is invalid" do
    expect {
      post "/api/v1/orders", params: {
        order: {
          client_account_id: client_account.id,
          listing_id: listing.id,
          payment_mode: "pay_later",
          items: [
            { product_variant_id: variant.id, quantity: 1 },
            { product_variant_id: variant.id, quantity: 0 }
          ]
        }
      }
    }.not_to change(Order, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(OrderItem.where(title: "Integrity photography - Standard")).to be_empty
    expect(ActivityEvent.where(event_type: "order.created")).to be_empty
  end

  it "does not sell an inactive variant" do
    variant.update!(active: false)

    expect {
      post "/api/v1/orders", params: {
        order: {
          client_account_id: client_account.id,
          listing_id: listing.id,
          payment_mode: "pay_later",
          items: [ { product_variant_id: variant.id, quantity: 1 } ]
        }
      }
    }.not_to change(Order, :count)

    expect(response).to have_http_status(:not_found)
  end
end
