class MakeAffiliateCodesUniqueRegardlessOfCase < ActiveRecord::Migration[8.0]
  # The code is typed by customers in any case, so COAST and coast are one code.
  # The model checked that; only the database can hold it under concurrent saves.
  def up
    duplicates = select_rows(<<~SQL)
      SELECT organization_id, LOWER(affiliate_id) FROM client_accounts
      WHERE affiliate_id IS NOT NULL GROUP BY 1, 2 HAVING COUNT(*) > 1
    SQL
    if duplicates.any?
      raise "Affiliate codes differ only by case in organizations #{duplicates.map(&:first).uniq.join(', ')}; rename them first"
    end

    remove_index :client_accounts, name: "index_client_accounts_on_organization_and_affiliate"
    add_index :client_accounts, "organization_id, LOWER(affiliate_id)", unique: true,
      where: "affiliate_id IS NOT NULL", name: "index_client_accounts_on_organization_and_affiliate"
  end

  def down
    remove_index :client_accounts, name: "index_client_accounts_on_organization_and_affiliate"
    add_index :client_accounts, [ :organization_id, :affiliate_id ], unique: true,
      where: "affiliate_id IS NOT NULL", name: "index_client_accounts_on_organization_and_affiliate"
  end
end
