class CreateAryeoIntegrationRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :integration_connections do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :provider, null: false
      t.text :api_key
      t.string :status, null: false, default: "disconnected"
      t.datetime :last_validated_at
      t.datetime :last_imported_at
      t.jsonb :endpoint_coverage, null: false, default: {}
      t.datetime :credentials_updated_at
      t.timestamps
    end
    add_index :integration_connections, %i[organization_id provider], unique: true

    create_table :integration_import_runs do |t|
      t.references :integration_connection, null: false, foreign_key: true
      t.references :organization, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :status, null: false, default: "pending"
      t.string :phase
      t.jsonb :counts, null: false, default: {}
      t.jsonb :coverage, null: false, default: {}
      t.jsonb :errors, null: false, default: []
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :integration_import_runs, %i[organization_id provider created_at]

    create_table :external_records do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :integration_connection, null: false, foreign_key: true
      t.references :integration_import_run, foreign_key: true
      t.string :provider, null: false
      t.string :resource_type, null: false
      t.string :external_id, null: false
      t.references :record, polymorphic: true
      t.jsonb :source_payload, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.string :sync_status, null: false, default: "imported"
      t.datetime :source_created_at
      t.datetime :source_updated_at
      t.datetime :last_imported_at
      t.timestamps
    end
    add_index :external_records, %i[integration_connection_id resource_type external_id], unique: true,
              name: "index_external_records_on_connection_resource_external_id"

    %i[users client_accounts listings orders invoices payments appointments workflow_tasks media_assets property_sites products].each do |table|
      add_column table, :origin, :string, null: false, default: "native"
      add_index table, :origin
    end
  end
end
