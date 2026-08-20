require "rails_helper"

RSpec.describe "Pricing configuration", type: :request do
  let(:organization) { Organization.create!(name: "Pricing Agency", slug: "pricing-config") }
  let(:other_organization) { Organization.create!(name: "Other Agency", slug: "other-pricing-config") }
  let!(:admin) { User.create!(organization:, name: "Admin", email: "pricing-admin@example.test", password: "long-enough-password", role: :organization_admin) }

  before { sign_in admin }

  it "creates a tax and rejects invalid rates" do
    post "/api/v1/taxes", params: { tax: { name: "GST", rate_basis_points: 500, scope: "custom" } }
    expect(response).to have_http_status(:created)

    sign_in admin
    post "/api/v1/taxes", params: { tax: { name: "PST", rate_basis_points: 10_001 } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects invalid coupon and travel-fee configuration" do
    post "/api/v1/coupons", params: { coupon: { code: "ZERO", discount_type: "fixed", amount_cents: 0 } }
    expect(response).to have_http_status(:unprocessable_content)

    sign_in admin
    post "/api/v1/travel_fees", params: { travel_fee: { name: "Remote", fee_type: "percentage", rate_basis_points: 0 } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "keeps coupon and travel-fee records tenant scoped" do
    coupon = other_organization.coupons.create!(code: "PRIVATE", amount_cents: 500)
    fee = other_organization.travel_fees.create!(name: "Remote", amount_cents: 2_500)

    patch "/api/v1/coupons/#{coupon.id}", params: { coupon: { active: false } }
    expect(response).to have_http_status(:not_found)

    sign_in admin
    delete "/api/v1/travel_fees/#{fee.id}"
    expect(response).to have_http_status(:not_found)
  end
end
