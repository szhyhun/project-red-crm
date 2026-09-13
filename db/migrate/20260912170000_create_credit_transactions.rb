class CreateCreditTransactions < ActiveRecord::Migration[8.0]
  def change
    # A person's credit is the sum of what was granted and spent, so every change
    # is a row with its reason rather than an overwritten number.
    create_table :credit_transactions do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :order, foreign_key: { on_delete: :nullify }
      t.integer :amount_cents, null: false
      t.integer :balance_after_cents, null: false
      t.string :reason, null: false
      t.timestamps
    end
    add_index :credit_transactions, [ :user_id, :created_at ]
    add_check_constraint :credit_transactions, "amount_cents <> 0", name: "credit_transactions_amount_not_zero"
    add_check_constraint :credit_transactions, "balance_after_cents >= 0", name: "credit_transactions_balance_not_negative"
    add_check_constraint :users, "credit_balance_cents >= 0", name: "users_credit_balance_not_negative"
  end
end
