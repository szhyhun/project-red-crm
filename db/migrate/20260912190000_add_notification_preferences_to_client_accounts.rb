class AddNotificationPreferencesToClientAccounts < ActiveRecord::Migration[8.0]
  def change
    # Event against channel, only where someone switched a default off: an
    # event or channel missing from the map is on.
    add_column :client_accounts, :notification_preferences, :jsonb, null: false, default: {}
  end
end
