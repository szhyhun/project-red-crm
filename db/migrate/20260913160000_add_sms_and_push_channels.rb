class AddSmsAndPushChannels < ActiveRecord::Migration[8.0]
  def change
    # A delivery goes out on one channel: email to an address, SMS to a phone
    # number, or push to every browser a person subscribed.
    add_column :notification_deliveries, :channel, :string, null: false, default: "email"
    add_check_constraint :notification_deliveries, "channel IN ('email', 'sms', 'push')", name: "notification_deliveries_channel_values"

    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :endpoint, null: false
      t.string :p256dh, null: false
      t.string :auth, null: false
      t.string :user_agent
      t.datetime :last_delivered_at
      t.timestamps
    end
    add_index :push_subscriptions, :endpoint, unique: true
  end
end
