class AddCreditAppliedToOrders < ActiveRecord::Migration[8.0]
  def change
    # Credit spent on an order is part of its total, so every invoice built
    # from the order already reflects it; the ledger row says whose it was.
    add_column :orders, :credit_applied_cents, :integer, null: false, default: 0
    add_check_constraint :orders, "credit_applied_cents >= 0", name: "orders_credit_applied_not_negative"
  end
end
