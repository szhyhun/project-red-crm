class RenameListingStartDateToImportStartDate < ActiveRecord::Migration[8.0]
  def change
    rename_column :integration_import_runs, :listing_start_date, :import_start_date
  end
end
