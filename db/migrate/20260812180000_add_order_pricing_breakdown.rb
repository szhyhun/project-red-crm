class AddOrderPricingBreakdown < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :discount_type, :string, null: false, default: "fixed"
    add_column :orders, :discount_rate_basis_points, :integer, null: false, default: 0
    add_column :orders, :fee_cents, :integer, null: false, default: 0
    add_column :orders, :fee_label, :string, null: false, default: "Service fee"

    add_column :invoices, :discount_cents, :integer, null: false, default: 0
    add_column :invoices, :fee_cents, :integer, null: false, default: 0
    add_column :invoices, :fee_label, :string, null: false, default: "Service fee"
  end
end
