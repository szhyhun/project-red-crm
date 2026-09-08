require "rails_helper"

RSpec.describe Order, type: :model do
  let!(:organization) { Organization.create!(name: "Financial Agency", slug: "financial-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Financial client", kind: :agent) }
  let!(:order) do
    Order.create!(organization:, client_account:, discount_cents: 500, tax_cents: 1_000, fee_cents: 250)
  end
  let!(:service) do
    organization.products.create!(slug: "financial-photo", title: "Financial photography", kind: :service,
                                  deliverable_type: "photography")
  end
  let!(:variant) { service.product_variants.create!(title: "Standard", price_cents: 10_000) }

  it "excludes cancelled order items from the billable subtotal" do
    order.order_items.create!(product: service, product_variant: variant, title: "Active service", quantity: 1,
                              unit_price_cents: 10_000, total_cents: 10_000)
    cancelled = order.order_items.create!(product: service, product_variant: variant, title: "Cancelled service",
                                          quantity: 1, unit_price_cents: 5_000, total_cents: 5_000)
    cancelled.update!(cancelled_at: Time.current)

    order.recalculate_totals!

    expect(order).to have_attributes(subtotal_cents: 10_000, total_cents: 10_750)
  end

  it "keeps operational deliverables out of invoice totals" do
    item = order.order_items.create!(product: service, product_variant: variant, title: service.title, quantity: 1,
                                     unit_price_cents: 10_000, total_cents: 10_000)
    order.order_deliverables.create!(organization:, order_item: item, service_product: service,
                                     title: service.title, deliverable_type: service.deliverable_type,
                                     materialization_key: "financial-deliverable-#{SecureRandom.uuid}")

    order.recalculate_totals!

    expect(order).to have_attributes(subtotal_cents: 10_000, total_cents: 10_750)
  end

  it "floors the total at zero when the fixed discount exceeds the subtotal" do
    order.update!(discount_cents: 20_000)
    order.order_items.create!(title: "Small service", quantity: 1, unit_price_cents: 1_000, total_cents: 1_000)

    order.recalculate_totals!

    expect(order).to have_attributes(subtotal_cents: 1_000, total_cents: 0)
  end

  it "reports an order without active invoices as unpaid" do
    order.invoices.create!(organization:, client_account:, number: "FIN-VOID", status: :void,
                           total_cents: 10_000, balance_due_cents: 10_000)

    expect(order.payment_status).to eq("unpaid")
    expect(order.balance_due_cents).to eq(0)
  end

  it "reports a partially paid order and sums active invoice balances" do
    order.invoices.create!(organization:, client_account:, number: "FIN-PARTIAL", status: :partially_paid,
                           total_cents: 10_000, balance_due_cents: 4_000)
    order.invoices.create!(organization:, client_account:, number: "FIN-VOID-PARTIAL", status: :void,
                           total_cents: 3_000, balance_due_cents: 3_000)

    expect(order.payment_status).to eq("partially_paid")
    expect(order.balance_due_cents).to eq(4_000)
  end

  it "reports paid only when every active invoice has no balance" do
    order.invoices.create!(organization:, client_account:, number: "FIN-PAID-1", status: :paid,
                           total_cents: 6_000, balance_due_cents: 0)
    order.invoices.create!(organization:, client_account:, number: "FIN-PAID-2", status: :paid,
                           total_cents: 4_000, balance_due_cents: 0)

    expect(order.payment_status).to eq("paid")
    expect(order.balance_due_cents).to eq(0)
  end
end
