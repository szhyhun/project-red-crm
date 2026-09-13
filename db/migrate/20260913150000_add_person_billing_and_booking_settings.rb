class AddPersonBillingAndBookingSettings < ActiveRecord::Migration[8.0]
  def change
    # Where a customer's invoices are addressed, on the person like Aryeo's.
    add_column :users, :billing_address, :jsonb, null: false, default: {}

    # Photographers a customer does not want sent to their shoots.
    create_table :customer_blocked_staff do |t|
      t.references :customer, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.references :staff, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.timestamps
    end
    add_index :customer_blocked_staff, [ :customer_id, :staff_id ], unique: true
  end
end
