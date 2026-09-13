class RetireCustomerTeams < ActiveRecord::Migration[8.0]
  # A customer team is a client account: it holds people, and a pricing plan is
  # applied to it directly. The older table grouped accounts, which Aryeo never
  # does, so each grouping becomes a team account of its own and whatever
  # pointed at it follows.
  def up
    execute <<~SQL
      CREATE TEMP TABLE retired_customer_teams ON COMMIT DROP AS
      SELECT customer_teams.id AS customer_team_id, nextval('client_accounts_id_seq') AS client_account_id, customer_teams.*
      FROM customer_teams;

      INSERT INTO client_accounts (id, organization_id, name, kind, brokerage_name, brokerage_website, website, logo_url,
                                   description, archived_at, origin, metadata, created_at, updated_at)
      SELECT client_account_id, organization_id, name, 'team', brokerage_name, brokerage_website, website, logo_url,
             description, CASE WHEN archived THEN updated_at END, origin,
             jsonb_build_object('retired_customer_team_id', customer_team_id), created_at, NOW()
      FROM retired_customer_teams;

      UPDATE pricing_plans SET client_account_id = retired.client_account_id, customer_team_id = NULL
      FROM retired_customer_teams retired WHERE pricing_plans.customer_team_id = retired.customer_team_id;

      UPDATE external_records SET record_type = 'ClientAccount', record_id = retired.client_account_id
      FROM retired_customer_teams retired
      WHERE external_records.record_type = 'CustomerTeam' AND external_records.record_id = retired.customer_team_id;

      -- The old table linked a team to accounts. The people of each linked
      -- account become members of the team, keeping their role and status.
      INSERT INTO client_memberships (client_account_id, user_id, role, status, invitation_accepted_at,
                                      listing_delivery_notification_enabled, created_at, updated_at)
      SELECT DISTINCT ON (retired.client_account_id, people.user_id)
             retired.client_account_id, people.user_id, people.role, people.status, people.invitation_accepted_at,
             people.listing_delivery_notification_enabled, NOW(), NOW()
      FROM customer_team_memberships links
      JOIN retired_customer_teams retired ON retired.customer_team_id = links.customer_team_id
      JOIN client_memberships people ON people.client_account_id = links.client_account_id
      ORDER BY retired.client_account_id, people.user_id, (people.role = 'admin') DESC
      ON CONFLICT (client_account_id, user_id) DO NOTHING;

      -- An account in exactly one team did its work for that team, so its
      -- listings, orders and invoices move there; the account stays linked to
      -- each listing so its people keep seeing them. An account in several
      -- teams cannot say which, so its work stays where it is.
      CREATE TEMP TABLE single_team_accounts ON COMMIT DROP AS
      SELECT links.client_account_id, MIN(retired.client_account_id) AS team_account_id
      FROM customer_team_memberships links
      JOIN retired_customer_teams retired ON retired.customer_team_id = links.customer_team_id
      GROUP BY links.client_account_id HAVING COUNT(*) = 1;

      INSERT INTO listing_customers (listing_id, client_account_id, created_at, updated_at)
      SELECT listings.id, listings.client_account_id, NOW(), NOW()
      FROM listings JOIN single_team_accounts moved ON moved.client_account_id = listings.client_account_id
      ON CONFLICT DO NOTHING;

      UPDATE listings SET client_account_id = moved.team_account_id
      FROM single_team_accounts moved WHERE listings.client_account_id = moved.client_account_id;
      UPDATE orders SET client_account_id = moved.team_account_id
      FROM single_team_accounts moved WHERE orders.client_account_id = moved.client_account_id;
      UPDATE invoices SET client_account_id = moved.team_account_id
      FROM single_team_accounts moved WHERE invoices.client_account_id = moved.client_account_id;
    SQL

    remove_check_constraint :pricing_plans, name: "pricing_plans_exactly_one_owner"
    remove_reference :pricing_plans, :customer_team, index: true, foreign_key: true
    add_check_constraint :pricing_plans,
      "(client_account_id IS NOT NULL)::int + (user_id IS NOT NULL)::int = 1",
      name: "pricing_plans_exactly_one_owner"

    drop_table :customer_team_memberships
    drop_table :customer_teams
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Customer teams were folded into client accounts"
  end
end
