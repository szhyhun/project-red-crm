class AddBillingMemberAndVisibilityToClientAccounts < ActiveRecord::Migration[8.0]
  VISIBILITY_BLOCKS = %w[billing pricing downloads marketing_templates].freeze

  def change
    # One member of the team carries the bill for everyone's orders. Settling
    # outside the system is a property of the team, not of each invoice.
    add_reference :client_accounts, :billing_user, foreign_key: { to_table: :users, on_delete: :nullify }, null: true
    add_column :client_accounts, :billing_pays_externally, :boolean, null: false, default: false

    # Each settings block is read-only for customers, and shown to the team's
    # admins, to everyone in it, or to nobody. Billing starts visible to everyone
    # because that is what the portal already shows.
    VISIBILITY_BLOCKS.each do |block|
      add_column :client_accounts, :"#{block}_visibility", :string, null: false,
        default: block == "billing" ? "everyone" : "hidden"
      add_check_constraint :client_accounts, "#{block}_visibility IN ('hidden', 'admins', 'everyone')",
        name: "client_accounts_#{block}_visibility_values"
    end
  end
end
