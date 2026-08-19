class RenameIntegrationImportRunErrors < ActiveRecord::Migration[8.0]
  def change
    rename_column :integration_import_runs, :errors, :error_details
  end
end
