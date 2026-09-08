class CreateMediaWorkflowFoundation < ActiveRecord::Migration[8.0]
  def change
    add_column :products, :deliverable_type, :string, null: false, default: "other"
    add_column :products, :sla_days, :integer, null: false, default: 0
    add_index :products, :deliverable_type

    add_column :orders, :approved_at, :datetime
    add_index :orders, :approved_at

    create_table :product_components do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :package_product, null: false, foreign_key: { to_table: :products }
      t.references :service_product, null: false, foreign_key: { to_table: :products }
      t.integer :quantity, null: false, default: 1
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :product_components, %i[package_product_id service_product_id], unique: true,
              name: "index_product_components_on_package_and_service"
    add_index :product_components, %i[package_product_id position],
              name: "index_product_components_on_package_position"

    create_table :order_deliverables do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :listing, foreign_key: true
      t.references :order, null: false, foreign_key: true
      t.references :order_item, null: false, foreign_key: true
      t.references :product_component, foreign_key: true
      t.references :service_product, null: false, foreign_key: { to_table: :products }
      t.string :title, null: false
      t.text :description
      t.string :deliverable_type, null: false
      t.integer :sla_days, null: false, default: 0
      t.integer :scope_sqft_min
      t.integer :scope_sqft_max
      t.string :scope_label
      t.string :status, null: false, default: "not_started"
      t.date :target_on
      t.datetime :delivered_at
      t.integer :delivery_version, null: false, default: 0
      t.integer :position, null: false, default: 0
      t.datetime :cancelled_at
      t.jsonb :metadata, null: false, default: {}
      t.string :materialization_key, null: false
      t.timestamps
    end
    add_index :order_deliverables, :materialization_key, unique: true
    add_index :order_deliverables, %i[order_id position]
    add_index :order_deliverables, %i[listing_id status]
    add_index :order_deliverables, %i[organization_id status]

    add_reference :media_assets, :order_deliverable, foreign_key: true
    add_column :media_assets, :version, :integer, null: false, default: 1
    add_reference :media_assets, :superseded_by, foreign_key: { to_table: :media_assets }
    add_index :media_assets, %i[order_deliverable_id version]

    add_reference :workflow_tasks, :parent_task, foreign_key: { to_table: :workflow_tasks }
    add_column :workflow_tasks, :task_kind, :string, null: false, default: "task"
    add_column :workflow_tasks, :workflow_group_key, :string
    add_index :workflow_tasks, %i[organization_id workflow_group_key]

    create_table :board_workflows do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :board, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.text :description
      t.boolean :enabled, null: false, default: true
      t.string :trigger_key, null: false, default: "order_approved"
      t.boolean :is_default, null: false, default: false
      t.integer :workflow_version, null: false, default: 1
      t.timestamps
    end
    add_index :board_workflows, %i[board_id name], unique: true
    add_index :board_workflows, %i[organization_id trigger_key enabled]

    create_table :board_workflow_conditions do |t|
      t.references :board_workflow, null: false, foreign_key: true
      t.string :field, null: false
      t.string :operator, null: false
      t.jsonb :value, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :board_workflow_conditions, %i[board_workflow_id position]

    create_table :board_workflow_actions do |t|
      t.references :board_workflow, null: false, foreign_key: true
      t.string :action_type, null: false
      t.jsonb :configuration, null: false, default: {}
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :board_workflow_actions, %i[board_workflow_id position]

    create_table :board_workflow_status_mappings do |t|
      t.references :board_workflow, null: false, foreign_key: true
      t.string :source_status, null: false
      t.string :target_column_key, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :board_workflow_status_mappings, %i[board_workflow_id source_status], unique: true,
              name: "index_workflow_status_mappings_on_workflow_and_source"

    create_table :board_workflow_runs do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :board_workflow, null: false, foreign_key: true
      t.references :order, null: false, foreign_key: true
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :triggered_at, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :retry_count, null: false, default: 0
      t.text :error
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :board_workflow_runs, :idempotency_key, unique: true
    add_index :board_workflow_runs, %i[organization_id status created_at]

    create_table :board_workflow_run_steps do |t|
      t.references :board_workflow_run, null: false, foreign_key: true
      t.references :board_workflow_action, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.integer :position, null: false, default: 0
      t.jsonb :input, null: false, default: {}
      t.jsonb :output, null: false, default: {}
      t.text :error
      t.timestamps
    end
    add_index :board_workflow_run_steps, %i[board_workflow_run_id position],
              name: "index_workflow_run_steps_on_run_and_position"

    create_table :workflow_task_placements do |t|
      t.references :workflow_task, null: false, foreign_key: true
      t.references :board, null: false, foreign_key: true
      t.references :workflow_column, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.boolean :is_home, null: false, default: false
      t.timestamps
    end
    add_index :workflow_task_placements, %i[workflow_task_id board_id], unique: true,
              name: "index_task_placements_on_task_and_board"
    add_index :workflow_task_placements, %i[board_id workflow_column_id position],
              name: "index_task_placements_on_board_column_position"
    add_index :workflow_task_placements, :workflow_task_id, unique: true, where: "is_home",
              name: "index_one_home_placement_per_task"

    create_table :workflow_task_deliverables do |t|
      t.references :workflow_task, null: false, foreign_key: true
      t.references :order_deliverable, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :workflow_task_deliverables, %i[workflow_task_id order_deliverable_id], unique: true,
              name: "index_task_deliverables_on_task_and_deliverable"

    add_column :messages, :message_kind, :string, null: false, default: "message"
    add_reference :messages, :listing, foreign_key: true
    add_reference :messages, :order_deliverable, foreign_key: true
    add_index :messages, %i[conversation_id message_kind created_at],
              name: "index_messages_on_conversation_kind_created_at"

    create_table :message_media_references do |t|
      t.references :message, null: false, foreign_key: true
      t.references :media_asset, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :message_media_references, %i[message_id media_asset_id], unique: true,
              name: "index_message_media_references_on_message_and_asset"
  end
end
