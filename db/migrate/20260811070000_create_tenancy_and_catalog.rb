class CreateTenancyAndCatalog < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :time_zone, null: false, default: "Pacific Time (US & Canada)"
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :organizations, :slug, unique: true

    add_reference :users, :organization, foreign_key: true
    add_column :users, :name, :string, null: false, default: ""
    add_column :users, :role, :string, null: false, default: "manager"
    add_column :users, :status, :string, null: false, default: "active"

    create_table :client_accounts do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.string :kind, null: false, default: "agent"
      t.string :email
      t.string :phone
      t.string :brokerage_name
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :client_accounts, %i[organization_id name]

    create_table :client_memberships do |t|
      t.references :client_account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.timestamps
    end
    add_index :client_memberships, %i[client_account_id user_id], unique: true,
              name: "index_client_memberships_on_client_and_user"

    create_table :products do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :external_source
      t.string :external_id
      t.string :slug, null: false
      t.string :title, null: false
      t.string :kind, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.boolean :bundle_candidate, null: false, default: false
      t.boolean :do_not_recommend, null: false, default: false
      t.jsonb :categories, null: false, default: []
      t.jsonb :capabilities, null: false, default: []
      t.jsonb :requires_capabilities, null: false, default: []
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end
    add_index :products, %i[organization_id slug], unique: true
    add_index :products, %i[organization_id external_source external_id], unique: true,
              name: "index_products_on_org_and_external_identity"

    create_table :product_variants do |t|
      t.references :product, null: false, foreign_key: true
      t.string :external_id
      t.string :title, null: false
      t.integer :price_cents, null: false
      t.integer :duration_minutes
      t.integer :sqft_min
      t.integer :sqft_max
      t.string :quantity_label
      t.boolean :active, null: false, default: true
      t.jsonb :source_payload, null: false, default: {}
      t.timestamps
    end
    add_index :product_variants, %i[product_id external_id], unique: true

    create_table :catalog_sync_runs do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :source, null: false
      t.string :status, null: false, default: "pending"
      t.integer :products_seen, null: false, default: 0
      t.integer :products_created, null: false, default: 0
      t.integer :products_updated, null: false, default: 0
      t.jsonb :unmapped_products, null: false, default: []
      t.jsonb :errors, null: false, default: []
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
  end
end
