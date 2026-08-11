class AddNotificationOutboxAndScheduleConstraint < ActiveRecord::Migration[8.0]
  def up
    create_table :notification_deliveries do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :notifiable, polymorphic: true, null: false
      t.string :kind, null: false
      t.string :recipient, null: false
      t.string :deduplication_key, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.text :last_error
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :notification_deliveries, :deduplication_key, unique: true
    add_index :notification_deliveries, %i[status created_at]

    enable_extension "btree_gist" unless extension_enabled?("btree_gist")
    execute <<~SQL
      ALTER TABLE appointments
      ADD CONSTRAINT no_overlapping_staff_appointments
      EXCLUDE USING gist (
        organization_id WITH =,
        assigned_user_id WITH =,
        tsrange(starts_at, ends_at, '[)') WITH &&
      )
      WHERE (assigned_user_id IS NOT NULL AND status <> 'cancelled')
    SQL
  end

  def down
    execute "ALTER TABLE appointments DROP CONSTRAINT IF EXISTS no_overlapping_staff_appointments"
    drop_table :notification_deliveries
  end
end
