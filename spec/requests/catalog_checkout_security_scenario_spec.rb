require "rails_helper"

RSpec.describe "Catalog checkout security API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Checkout security agency", slug: "checkout-security-agency") }
  let!(:other_organization) { Organization.create!(name: "Other checkout security agency", slug: "other-checkout-security-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Checkout manager", email: "checkout-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:staff) do
    User.create!(organization:, name: "Checkout staff", email: "checkout-staff@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Checkout client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "14 Checkout Street") }
  let!(:service) do
    organization.products.create!(slug: "checkout-photography", title: "Checkout photography", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 20_000) }

  before { sign_in manager }

  it "does not accept a product variant from another organization" do
    foreign_service = other_organization.products.create!(slug: "foreign-checkout-service", title: "Foreign service",
                                                           kind: :service, deliverable_type: "photography")
    foreign_variant = foreign_service.product_variants.create!(title: "Foreign standard", price_cents: 10_000)

    expect {
      post "/api/v1/orders", params: {
        order: {
          client_account_id: client_account.id,
          listing_id: listing.id,
          payment_mode: "pay_later",
          items: [ { product_variant_id: foreign_variant.id, quantity: 1 } ]
        }
      }
    }.not_to change(Order, :count)

    expect(response).to have_http_status(:not_found)
  end

  it "does not sell a variant after its product is deactivated" do
    service.update!(active: false)

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

  it "does not let production staff create commercial orders" do
    sign_out manager
    sign_in staff

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

    expect(response).to have_http_status(:forbidden)
  end

  it "does not create an order for a non-positive quantity" do
    expect {
      post "/api/v1/orders", params: {
        order: {
          client_account_id: client_account.id,
          listing_id: listing.id,
          payment_mode: "pay_later",
          items: [ { product_variant_id: variant.id, quantity: 0 } ]
        }
      }
    }.not_to change(Order, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("must be greater than 0")
  end
end
