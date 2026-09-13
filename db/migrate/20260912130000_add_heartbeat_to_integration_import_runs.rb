class AddHeartbeatToIntegrationImportRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :integration_import_runs, :heartbeat_at, :datetime
    add_index :integration_import_runs, %i[status heartbeat_at]
  end
end
