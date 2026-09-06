class AddPropertyFieldsToListings < ActiveRecord::Migration[8.0]
  def change
    add_column :listings, :property_status, :string, default: "coming_soon", null: false
    add_column :listings, :property_type, :string
    add_column :listings, :price_cents, :integer
    add_column :listings, :lot_acres, :decimal, precision: 8, scale: 3
    add_column :listings, :parking, :string
    add_column :listings, :year_built, :integer
    add_column :listings, :mls_live_date, :date

    add_index :listings, [ :organization_id, :property_status ]
  end
end
