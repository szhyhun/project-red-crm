require "rails_helper"

RSpec.describe Orders::Create, type: :interactor do
  let!(:organization) { Organization.create!(name: "Customer rules agency", slug: "customer-rules-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Rules manager", email: "rules-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:account) { ClientAccount.create!(organization:, name: "Rules Team", kind: :team) }
  let!(:customer) do
    User.create!(organization:, name: "Rules customer", email: "rules-customer@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: account, user:, role: :admin, status: :active, is_default: true)
    end
  end
  let!(:product) { Product.create!(organization:, slug: "rules-photography", title: "Rules photography", kind: :service) }
  let!(:variant) { product.product_variants.create!(title: "Standard", price_cents: 30_000) }

  def create_order(ordered_by)
    described_class.call(
      organization:,
      ordered_by:,
      attributes: { client_account_id: account.id, payment_mode: "pay_later", items: [ { product_variant_id: variant.id, quantity: 1 } ] }
    )
  end

  it "refuses an order from a customer who is blocked from ordering" do
    customer.update!(blocked_from_ordering: true)

    result = nil
    expect { result = create_order(customer) }.not_to change(Order, :count)

    expect(result).to be_failure
    expect(result.failure.code).to eq("order_create_invalid")
    expect(result.failure.message).to include("This customer cannot place orders")
  end

  it "still lets staff place an order for a blocked customer's team" do
    customer.update!(blocked_from_ordering: true)

    expect(create_order(manager)).to be_success
  end

  it "charges the team's plan when the person has no override" do
    organization.pricing_plans.create!(name: "Team rate", client_account: account)
                .pricing_plan_prices.create!(product_variant: variant, price_cents: 25_000)

    order = create_order(customer).fetch(:order)

    expect(order.order_items.sole.unit_price_cents).to eq(25_000)
  end

  it "lets a price promised to one person beat their team's plan" do
    organization.pricing_plans.create!(name: "Team rate", client_account: account)
                .pricing_plan_prices.create!(product_variant: variant, price_cents: 25_000)
    organization.pricing_plans.create!(name: "Promised rate", user: customer)
                .pricing_plan_prices.create!(product_variant: variant, price_cents: 19_900)

    order = create_order(customer).fetch(:order)

    expect(order.order_items.sole.unit_price_cents).to eq(19_900)
  end
end
