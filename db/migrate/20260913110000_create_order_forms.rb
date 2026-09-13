class CreateOrderForms < ActiveRecord::Migration[8.0]
  def change
    # An order form is the set of services a customer may book, with a note at
    # the top. A team can be given its own; a team without one books from the
    # whole active catalog.
    create_table :order_forms do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :order_forms, [ :organization_id, :name ], unique: true

    create_table :order_form_products do |t|
      t.references :order_form, null: false, foreign_key: { on_delete: :cascade }
      t.references :product, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :order_form_products, [ :order_form_id, :product_id ], unique: true

    add_reference :client_accounts, :order_form, foreign_key: { on_delete: :nullify }
  end
end
