class AddRetentionPeriodToConversations < ActiveRecord::Migration[8.0]
  RETENTION_PERIODS = %w[two_months six_months one_year forever].freeze

  def up
    add_column :conversations, :retention_period, :string, null: false, default: "two_months"
    add_index :conversations, :retention_period
    add_check_constraint :conversations,
                         "retention_period IN (#{RETENTION_PERIODS.map { |value| "'#{value}'" }.join(", ")})",
                         name: "conversations_retention_period_values"
  end

  def down
    remove_check_constraint :conversations, name: "conversations_retention_period_values"
    remove_index :conversations, :retention_period
    remove_column :conversations, :retention_period
  end
end
