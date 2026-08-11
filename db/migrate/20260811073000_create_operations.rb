class CreateOperations < ActiveRecord::Migration[8.0]
  def change
    create_table :listings do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :client_account, null: false, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.string :public_slug
      t.string :address_line_1, null: false
      t.string :address_line_2
      t.string :city
      t.string :province
      t.string :postal_code
      t.string :country, null: false, default: "CA"
      t.integer :square_feet
      t.integer :bedrooms
      t.decimal :bathrooms, precision: 4, scale: 1
      t.datetime :scheduled_at
      t.datetime :delivered_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :listings, %i[organization_id public_slug], unique: true
    add_index :listings, %i[organization_id status]

    create_table :orders do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :client_account, null: false, foreign_key: true
      t.references :listing, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.string :payment_mode, null: false, default: "pay_later"
      t.string :currency, null: false, default: "cad"
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :discount_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.string :source, null: false, default: "crm"
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :orders, %i[organization_id status]

    create_table :order_items do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, foreign_key: true
      t.references :product_variant, foreign_key: true
      t.string :title, null: false
      t.integer :quantity, null: false, default: 1
      t.integer :unit_price_cents, null: false
      t.integer :total_cents, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.timestamps
    end

    create_table :appointments do |t|
      t.references :listing, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.references :assigned_user, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "scheduled"
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.text :notes
      t.timestamps
    end
    add_index :appointments, %i[organization_id starts_at]

    create_table :listing_assignments do |t|
      t.references :listing, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false
      t.timestamps
    end
    add_index :listing_assignments, %i[listing_id user_id role], unique: true,
              name: "index_listing_assignments_on_listing_user_role"

    create_table :workflow_tasks do |t|
      t.references :listing, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.references :assignee, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.string :status, null: false, default: "todo"
      t.string :stage, null: false, default: "intake"
      t.boolean :customer_visible, null: false, default: false
      t.integer :position, null: false, default: 0
      t.datetime :due_at
      t.datetime :completed_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :workflow_tasks, %i[organization_id status stage]

    create_table :media_assets do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :listing, foreign_key: true
      t.references :uploaded_by, foreign_key: { to_table: :users }
      t.string :kind, null: false, default: "final"
      t.string :status, null: false, default: "pending"
      t.string :storage_key, null: false
      t.string :filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size
      t.integer :width
      t.integer :height
      t.integer :duration_seconds
      t.jsonb :metadata, null: false, default: {}
      t.datetime :processed_at
      t.timestamps
    end
    add_index :media_assets, %i[organization_id status]
    add_index :media_assets, :storage_key, unique: true

    create_table :activity_events do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.string :event_type, null: false
      t.references :subject, polymorphic: true, null: false
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end
    add_index :activity_events, %i[organization_id created_at]
  end
end
