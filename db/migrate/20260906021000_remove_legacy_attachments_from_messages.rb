class RemoveLegacyAttachmentsFromMessages < ActiveRecord::Migration[8.0]
  def change
    remove_column :messages, :attachments, :jsonb
  end
end
