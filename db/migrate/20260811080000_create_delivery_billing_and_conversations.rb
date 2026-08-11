class CreateDeliveryBillingAndConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :property_sites do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :listing, null: false, foreign_key: true
      t.string :slug, null: false
      t.string :status, null: false, default: "draft"
      t.string :custom_domain
      t.datetime :published_at
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :property_sites, %i[organization_id slug], unique: true

    create_table :invoices do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :client_account, null: false, foreign_key: true
      t.references :listing, foreign_key: true
      t.references :order, foreign_key: true
      t.string :number, null: false
      t.string :status, null: false, default: "draft"
      t.string :currency, null: false, default: "cad"
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.integer :balance_due_cents, null: false, default: 0
      t.date :due_on
      t.datetime :sent_at
      t.datetime :paid_at
      t.string :payment_provider
      t.string :provider_invoice_id
      t.timestamps
    end
    add_index :invoices, %i[organization_id number], unique: true
    add_index :invoices, %i[organization_id status]

    create_table :payments do |t|
      t.references :invoice, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :provider_payment_id
      t.string :status, null: false, default: "pending"
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "cad"
      t.datetime :paid_at
      t.jsonb :provider_payload, null: false, default: {}
      t.timestamps
    end
    add_index :payments, %i[provider provider_payment_id], unique: true

    create_table :conversations do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :listing, foreign_key: true
      t.references :client_account, foreign_key: true
      t.string :kind, null: false, default: "internal"
      t.string :subject
      t.datetime :last_message_at
      t.timestamps
    end
    add_index :conversations, %i[organization_id kind last_message_at]

    create_table :conversation_memberships do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "participant"
      t.datetime :last_read_at
      t.timestamps
    end
    add_index :conversation_memberships, %i[conversation_id user_id], unique: true,
              name: "index_conversation_memberships_on_conversation_and_user"

    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.string :visibility, null: false, default: "participants"
      t.jsonb :attachments, null: false, default: []
      t.timestamps
    end
    add_index :messages, %i[conversation_id created_at]
  end
end
