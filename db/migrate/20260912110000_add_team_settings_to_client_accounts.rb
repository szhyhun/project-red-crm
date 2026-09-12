class AddTeamSettingsToClientAccounts < ActiveRecord::Migration[8.0]
  def change
    # A customer team is more than a name: it carries the identity shown on a
    # property site, a note for our own staff, and the settings that apply to
    # everyone ordering under it.
    add_column :client_accounts, :description, :text
    add_column :client_accounts, :internal_note, :text
    add_column :client_accounts, :logo_url, :string
    add_column :client_accounts, :website, :string
    add_column :client_accounts, :brokerage_website, :string
    add_column :client_accounts, :affiliate_id, :string
    add_column :client_accounts, :archived_at, :datetime

    add_column :client_accounts, :lock_downloads_before_payment, :boolean, null: false, default: false
    add_column :client_accounts, :display_original_price, :boolean, null: false, default: true
    add_column :client_accounts, :suppress_payment_reminders, :boolean, null: false, default: false

    # Entering the code on an order form is how a member attaches their order to
    # a team, so it has to identify exactly one of them.
    add_index :client_accounts, [ :organization_id, :affiliate_id ], unique: true,
      where: "affiliate_id IS NOT NULL", name: "index_client_accounts_on_organization_and_affiliate"
    add_index :client_accounts, [ :organization_id, :archived_at ], name: "index_client_accounts_on_organization_and_archived"
  end
end
