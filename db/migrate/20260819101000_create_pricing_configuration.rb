class CreatePricingConfiguration < ActiveRecord::Migration[8.0]
  def change
    create_table :taxes do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :rate_basis_points, null: false, default: 0
      t.string :scope, null: false, default: "custom"
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :taxes, "organization_id, lower(name)", unique: true, name: "index_taxes_on_organization_and_lower_name"
    add_index :taxes, [ :organization_id, :active ]

    create_table :coupons do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :code, null: false
      t.string :description
      t.string :discount_type, null: false, default: "fixed"
      t.integer :amount_cents, null: false, default: 0
      t.integer :rate_basis_points, null: false, default: 0
      t.datetime :starts_at
      t.datetime :ends_at
      t.integer :max_redemptions
      t.integer :redemption_count, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :coupons, [ :organization_id, :code ], unique: true

    create_table :travel_fees do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :fee_type, null: false, default: "flat"
      t.integer :amount_cents, null: false, default: 0
      t.integer :rate_basis_points, null: false, default: 0
      t.integer :free_within_km
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :travel_fees, [ :organization_id, :active ]
  end
end
