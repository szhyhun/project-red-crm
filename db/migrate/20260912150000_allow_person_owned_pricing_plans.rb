class AllowPersonOwnedPricingPlans < ActiveRecord::Migration[8.0]
  def up
    # A price can be promised to one person as well as to an account or a team.
    # The database keeps the same guarantee as before -- exactly one owner --
    # now counted across all three.
    remove_check_constraint :pricing_plans, name: "pricing_plans_exactly_one_owner"
    add_check_constraint :pricing_plans,
                         "(client_account_id IS NOT NULL)::int + (customer_team_id IS NOT NULL)::int + (user_id IS NOT NULL)::int = 1",
                         name: "pricing_plans_exactly_one_owner"
  end

  def down
    remove_check_constraint :pricing_plans, name: "pricing_plans_exactly_one_owner"
    add_check_constraint :pricing_plans,
                         "client_account_id IS NOT NULL AND customer_team_id IS NULL OR client_account_id IS NULL AND customer_team_id IS NOT NULL",
                         name: "pricing_plans_exactly_one_owner"
  end
end
