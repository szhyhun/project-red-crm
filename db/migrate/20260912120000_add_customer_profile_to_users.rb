class AddCustomerProfileToUsers < ActiveRecord::Migration[8.0]
  def change
    # A customer user is a person, not only a login: the licence that reaches a
    # property site, the note our staff keep, and the standing that decides
    # whether they may order at all.
    add_column :users, :phone, :string
    add_column :users, :license_number, :string
    add_column :users, :avatar_url, :string
    add_column :users, :timezone, :string
    add_column :users, :internal_note, :text
    add_column :users, :social_profiles, :jsonb, null: false, default: {}
    add_column :users, :blocked_from_ordering, :boolean, null: false, default: false
    add_column :users, :credit_balance_cents, :integer, null: false, default: 0

    # A price promised to one person outranks any team they are on, which is
    # the third owner a pricing plan can have.
    add_reference :pricing_plans, :user, foreign_key: true, index: false
    add_index :pricing_plans, [ :user_id, :active ], name: "index_pricing_plans_on_user_and_active"
  end
end
