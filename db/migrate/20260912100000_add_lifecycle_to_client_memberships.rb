class AddLifecycleToClientMemberships < ActiveRecord::Migration[8.0]
  def up
    # A membership was a row that either existed or did not. It now carries the
    # lifecycle it always implied: invited before it grants anything, revoked or
    # archived instead of vanishing, and one of a person's teams marked as the
    # one they land in.
    add_column :client_memberships, :status, :string, null: false, default: "active"
    add_column :client_memberships, :invitation_accepted_at, :datetime
    add_column :client_memberships, :is_default, :boolean, null: false, default: false
    add_column :client_memberships, :listing_delivery_notification_enabled, :boolean, null: false, default: true

    add_index :client_memberships, [ :user_id, :status ], name: "index_client_memberships_on_user_and_status"
    # One landing team per person, enforced where it cannot drift.
    add_index :client_memberships, :user_id, unique: true, where: "is_default", name: "index_one_default_client_membership_per_user"

    # Everyone who already had access keeps it, dated from when they were added,
    # and their first team becomes the one they land in.
    execute <<~SQL
      UPDATE client_memberships SET invitation_accepted_at = created_at WHERE invitation_accepted_at IS NULL
    SQL
    execute <<~SQL
      UPDATE client_memberships SET is_default = TRUE
      WHERE id IN (
        SELECT DISTINCT ON (user_id) id FROM client_memberships ORDER BY user_id, created_at, id
      )
    SQL
  end

  def down
    remove_index :client_memberships, name: "index_one_default_client_membership_per_user"
    remove_index :client_memberships, name: "index_client_memberships_on_user_and_status"
    remove_column :client_memberships, :listing_delivery_notification_enabled
    remove_column :client_memberships, :is_default
    remove_column :client_memberships, :invitation_accepted_at
    remove_column :client_memberships, :status
  end
end
