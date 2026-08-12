class AddListingWorkspaceRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :listing_notes do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :listing, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.string :note_type, null: false, default: "listing"
      t.text :body, null: false
      t.timestamps
    end

    add_index :listing_notes, %i[listing_id note_type created_at]

    create_table :payroll_items do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :listing, null: false, foreign_key: true
      t.references :order, foreign_key: true
      t.references :order_item, foreign_key: true
      t.references :team_member, foreign_key: { to_table: :users }
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.text :notes
      t.integer :amount_cents, null: false
      t.datetime :submitted_at
      t.datetime :paid_at
      t.string :status, null: false, default: "draft"
      t.timestamps
    end

    add_index :payroll_items, %i[organization_id status submitted_at]
    add_index :payroll_items, %i[listing_id status]

    create_table :listing_feedbacks do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :listing, null: false, foreign_key: true
      t.references :client_account, null: false, foreign_key: true
      t.references :order, foreign_key: true
      t.integer :delivery_rating
      t.integer :service_rating
      t.integer :media_rating
      t.text :comment
      t.string :follow_up_status, null: false, default: "none"
      t.datetime :requested_at
      t.datetime :submitted_at
      t.timestamps
    end

    add_index :listing_feedbacks, %i[listing_id submitted_at]
    add_index :listing_feedbacks, %i[organization_id follow_up_status]

    add_column :media_assets, :category, :string, null: false, default: "files"
    add_column :media_assets, :customer_visible, :boolean, null: false, default: true
    add_index :media_assets, %i[listing_id category]

    add_reference :appointments, :order, foreign_key: true
    add_column :appointments, :completed_at, :datetime
  end
end
