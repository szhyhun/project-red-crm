class AddImportOptionsToIntegrationImportRuns < ActiveRecord::Migration[8.0]
  def change
    add_column :integration_import_runs, :requested_resources, :jsonb, null: false, default: []
    add_column :integration_import_runs, :listing_start_date, :date
    add_column :integration_import_runs, :conflict_resolution, :string, null: false, default: "skip"
  end
end
