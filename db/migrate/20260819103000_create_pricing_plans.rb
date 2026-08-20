class CreatePricingPlans < ActiveRecord::Migration[8.0]
  def change
    create_table :pricing_plans do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.references :client_account, foreign_key: true
      t.references :customer_team, foreign_key: true
      t.references :coupon, foreign_key: true
      t.integer :priority, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_check_constraint :pricing_plans,
                         "(client_account_id IS NOT NULL AND customer_team_id IS NULL) OR (client_account_id IS NULL AND customer_team_id IS NOT NULL)",
                         name: "pricing_plans_exactly_one_owner"
    add_index :pricing_plans, [ :organization_id, :active ]
    add_index :pricing_plans, [ :client_account_id, :active ]
    add_index :pricing_plans, [ :customer_team_id, :active, :priority ]

    create_table :pricing_plan_prices do |t|
      t.references :pricing_plan, null: false, foreign_key: true
      t.references :product_variant, null: false, foreign_key: true
      t.integer :price_cents, null: false
      t.timestamps
    end
    add_index :pricing_plan_prices, [ :pricing_plan_id, :product_variant_id ], unique: true
  end
end
