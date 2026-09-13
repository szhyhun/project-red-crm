class CreateListingMemberships < ActiveRecord::Migration[8.0]
  def change
    # Aryeo gives a listing to the memberships attached to it rather than to the
    # whole team. A team chooses: its members see all of its listings, as they
    # always have, or only the ones they booked or were given. Admins always
    # see everything.
    add_column :client_accounts, :member_listing_access, :string, null: false, default: "all_team_listings"
    add_check_constraint :client_accounts, "member_listing_access IN ('all_team_listings', 'attached_listings')",
      name: "client_accounts_member_listing_access_values"

    create_table :listing_memberships do |t|
      t.references :listing, null: false, foreign_key: { on_delete: :cascade }
      t.references :client_membership, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :listing_memberships, [ :listing_id, :client_membership_id ], unique: true
  end
end
