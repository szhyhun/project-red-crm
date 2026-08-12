require "rails_helper"

RSpec.describe Invoices::Creator do
  it "creates one invoice per order and carries over the order total" do
    organization = Organization.create!(name: "ProjectRed", slug: "projectred")
    client = ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent)
    order = Order.create!(organization:, client_account: client, subtotal_cents: 45_000, discount_cents: 500,
                          tax_cents: 2_250, fee_cents: 750, fee_label: "Rush fee", total_cents: 47_500)

    first_invoice = described_class.new(organization:, order:).create!
    same_invoice = described_class.new(organization:, order:).create!

    expect(first_invoice).to have_attributes(number: "PR-000001", discount_cents: 500, fee_cents: 750,
                                              fee_label: "Rush fee", total_cents: 47_500, balance_due_cents: 47_500)
    expect(same_invoice.id).to eq(first_invoice.id)
    expect(order.reload).to be_invoiced
  end
end
