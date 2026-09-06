class CreateConversationAttachments < ActiveRecord::Migration[8.0]
  def change
    create_table :conversation_attachments do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :message, null: false, foreign_key: true
      t.references :uploaded_by, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "pending"
      t.string :storage_key, null: false
      t.string :filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.datetime :processed_at
      t.timestamps
    end

    add_index :conversation_attachments, :storage_key, unique: true
    add_index :conversation_attachments, [ :message_id, :created_at ]
    add_index :conversation_attachments, [ :conversation_id, :created_at ]
  end
end
