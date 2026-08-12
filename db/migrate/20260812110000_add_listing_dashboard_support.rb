class AddListingDashboardSupport < ActiveRecord::Migration[8.0]
  def change
    add_column :listings, :delivery_status, :string, null: false, default: "undelivered"
    add_column :listings, :zillow_showcase, :boolean, null: false, default: false
    add_column :listings, :mls_number, :string
    add_column :listings, :tags, :string, array: true, null: false, default: []
    add_index :listings, %i[organization_id delivery_status]
    add_index :listings, :tags, using: :gin

    add_column :orders, :fulfillment_status, :string, null: false, default: "unfulfilled"
    add_column :orders, :tags, :string, array: true, null: false, default: []
    add_index :orders, %i[organization_id fulfillment_status]
    add_index :orders, :tags, using: :gin

    add_column :appointments, :request_status, :string, null: false, default: "not_requested"
    add_index :appointments, %i[organization_id request_status]

    create_table :saved_listing_views do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :access, null: false, default: "personal"
      t.jsonb :filters, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :saved_listing_views, %i[organization_id user_id name], unique: true
    add_index :saved_listing_views, %i[organization_id position]

    create_table :listing_view_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :display_mode, null: false, default: "grid"
      t.jsonb :saved_view_order, null: false, default: []
      t.timestamps
    end
  end
end
