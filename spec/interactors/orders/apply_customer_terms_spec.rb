require "rails_helper"

RSpec.describe Orders::ApplyCustomerTerms, type: :interactor do
  let!(:organization) { Organization.create!(name: "Terms agency", slug: "terms-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Terms manager", email: "terms-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:account) { ClientAccount.create!(organization:, name: "Terms Team", kind: :team) }
  let!(:payer) { customer("terms-payer", :admin) }
  let!(:agent) { customer("terms-agent", :member) }

  def customer(handle, role)
    User.create!(organization:, name: handle.humanize, email: "#{handle}@example.test",
                 password: "long-enough-password", role: role == :admin ? :client_admin : :client_member).tap do |user|
      ClientMembership.create!(client_account: account, user:, role:, status: :active, is_default: true)
    end
  end

  let!(:product) { Product.create!(organization:, slug: "terms-photos", title: "Terms photos", kind: :service) }
  let!(:variant) { product.product_variants.create!(title: "Standard", price_cents: 30_000) }

  def order_for(total_cents, payment_mode: :pay_now)
    order = Order.new(organization:, client_account: account, payment_mode:)
    order.order_items.build(product:, product_variant: variant, title: "Terms photos", quantity: 1,
                            unit_price_cents: total_cents, total_cents:)
    order.recalculate_totals!
    order.tap(&:save!)
  end

  def grant(person, cents)
    CustomerUsers::AdjustCredit.call(person:, actor: manager, amount_cents: cents, reason: "Goodwill")
  end

  it "spends nobody's credit and asks nobody to pay when the team pays outside the system" do
    account.update!(billing_user: payer, billing_pays_externally: true)
    grant(payer, 10_000)
    order = order_for(30_000)

    described_class.call(order:, ordered_by: agent)

    expect(order.reload).to have_attributes(payment_mode: "pay_later", credit_applied_cents: 0, total_cents: 30_000)
    expect(payer.reload.credit_balance_cents).to eq(10_000)
  end

  it "does not ask a member to pay up front, and spends the billing member's credit rather than theirs" do
    account.update!(billing_user: payer)
    grant(payer, 10_000)
    grant(agent, 5_000)
    order = order_for(30_000)

    described_class.call(order:, ordered_by: agent)

    expect(order.reload).to have_attributes(payment_mode: "pay_later", credit_applied_cents: 10_000, total_cents: 20_000)
    expect(payer.reload.credit_balance_cents).to eq(0)
    expect(agent.reload.credit_balance_cents).to eq(5_000)
    expect(CreditTransaction.find_by!(user: payer, order:)).to have_attributes(amount_cents: -10_000, reason: "Applied to order ##{order.id}")
  end

  it "spends only as much of a customer's own credit as the order costs, and only once" do
    grant(agent, 50_000)
    order = order_for(30_000)

    2.times { described_class.call(order:, ordered_by: agent) }

    expect(order.reload).to have_attributes(payment_mode: "pay_now", credit_applied_cents: 30_000, total_cents: 0)
    expect(agent.reload.credit_balance_cents).to eq(20_000)
  end

  it "spends no one's credit on an order staff place for a team without a billing member" do
    grant(agent, 5_000)
    order = order_for(30_000)

    described_class.call(order:, ordered_by: manager)

    expect(order.reload.credit_applied_cents).to eq(0)
  end

  describe Orders::RebalanceCredit do
    it "returns credit when the order shrinks below it, and all of it when the order is cancelled" do
      grant(agent, 30_000)
      order = order_for(30_000)
      Orders::ApplyCustomerTerms.call(order:, ordered_by: agent)
      expect(order.reload).to have_attributes(credit_applied_cents: 30_000, total_cents: 0)

      order.update!(discount_cents: 10_000)
      order.recalculate_totals!
      order.save!
      Orders::RebalanceCredit.call(order:, actor: manager)
      expect(order.reload).to have_attributes(credit_applied_cents: 20_000, total_cents: 0)
      expect(agent.reload.credit_balance_cents).to eq(10_000)

      order.update!(status: :cancelled)
      Orders::RebalanceCredit.call(order:, actor: manager)
      expect(order.reload.credit_applied_cents).to eq(0)
      expect(agent.reload.credit_balance_cents).to eq(30_000)
      expect(CreditTransaction.where(user: agent).order(:id).pluck(:amount_cents)).to eq([ 30_000, -30_000, 10_000, 20_000 ])
    end

    it "leaves an order alone that still costs at least its credit" do
      grant(agent, 10_000)
      order = order_for(30_000)
      Orders::ApplyCustomerTerms.call(order:, ordered_by: agent)

      expect(Orders::RebalanceCredit.call(order:, actor: manager)[:refunded_cents]).to be_nil
      expect(agent.reload.credit_balance_cents).to eq(0)
    end
  end
end
