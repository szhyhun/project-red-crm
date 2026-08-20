require "rails_helper"

RSpec.describe Coupon, type: :model do
  let(:organization) { Organization.create!(name: "Coupon Agency", slug: "coupon-agency") }

  it "normalizes code and expires after its redemption limit" do
    coupon = organization.coupons.create!(code: " summer ", discount_type: :percentage, rate_basis_points: 1_500,
                                           max_redemptions: 1)

    expect(coupon.code).to eq("SUMMER")
    expect(coupon).to be_redeemable

    coupon.update!(redemption_count: 1)
    expect(coupon).not_to be_redeemable
    expect(Coupon.redeemable).not_to include(coupon)
  end

  it "rejects invalid fixed and expired coupon configuration" do
    coupon = organization.coupons.new(code: "NOPE", discount_type: :fixed, amount_cents: 0,
                                      starts_at: Time.current, ends_at: 1.hour.ago)

    expect(coupon).not_to be_valid
    expect(coupon.errors[:amount_cents]).to be_present
    expect(coupon.errors[:ends_at]).to be_present
  end
end
