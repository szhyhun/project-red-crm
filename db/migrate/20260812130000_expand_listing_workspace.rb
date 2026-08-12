class ExpandListingWorkspace < ActiveRecord::Migration[8.0]
  def up
    create_table :listing_customers do |t|
      t.references :listing, null: false, foreign_key: true
      t.references :client_account, null: false, foreign_key: true
      t.boolean :primary, null: false, default: false
      t.boolean :marketing_visible, null: false, default: true
      t.timestamps
    end
    add_index :listing_customers, %i[listing_id client_account_id], unique: true

    create_table :appointment_team_members do |t|
      t.references :appointment, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "team_member"
      t.timestamps
    end
    add_index :appointment_team_members, %i[appointment_id user_id], unique: true

    create_table :appointment_events do |t|
      t.references :appointment, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :event_type, null: false
      t.jsonb :changeset, null: false, default: {}
      t.timestamps
    end
    add_index :appointment_events, %i[appointment_id created_at]

    create_table :appointment_items do |t|
      t.references :appointment, null: false, foreign_key: true
      t.references :order_item, foreign_key: true
      t.string :title, null: false
      t.integer :quantity, null: false, default: 1
      t.timestamps
    end

    create_table :listing_custom_fields do |t|
      t.references :listing, null: false, foreign_key: true
      t.string :name, null: false
      t.text :value
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :listing_custom_fields, %i[listing_id position]

    execute <<~SQL.squish
      INSERT INTO listing_customers (listing_id, client_account_id, "primary", marketing_visible, created_at, updated_at)
      SELECT id, client_account_id, TRUE, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP FROM listings
      ON CONFLICT (listing_id, client_account_id) DO NOTHING
    SQL
  end

  def down
    drop_table :listing_custom_fields
    drop_table :appointment_items
    drop_table :appointment_events
    drop_table :appointment_team_members
    drop_table :listing_customers
  end
end
