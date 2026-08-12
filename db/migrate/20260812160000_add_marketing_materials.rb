class AddMarketingMaterials < ActiveRecord::Migration[8.0]
  def change
    add_column :property_sites, :customer_visible, :boolean, null: false, default: true
    add_column :property_sites, :site_kind, :string, null: false, default: "branded"

    create_table :marketing_materials do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :listing, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :material_type, null: false
      t.string :title, null: false
      t.string :status, null: false, default: "draft"
      t.boolean :customer_visible, null: false, default: true
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :marketing_materials, %i[listing_id status]
  end
end
