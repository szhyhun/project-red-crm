class AddCreatedAtIndexToMessages < ActiveRecord::Migration[8.0]
  def change
    add_index :messages, :created_at unless index_exists?(:messages, :created_at)
  end
end
