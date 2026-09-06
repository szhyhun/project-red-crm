require "rails_helper"
require Rails.root.join("db/migrate/20260905200000_rename_listing_start_date_to_import_start_date").to_s

# The rename must preserve dates already saved by the first listing-only import
# option; losing that value would silently change the meaning of old runs.
RSpec.describe RenameListingStartDateToImportStartDate, type: :migration do
  around do |example|
    ActiveRecord::Base.connection.transaction(requires_new: true) do
      described_class.new.down
      IntegrationImportRun.reset_column_information

      organization = Organization.create!(name: "Migration Org", slug: "migration-import-date")
      connection = organization.integration_connections.create!(provider: :aryeo, api_key: "aryeo-key", status: :connected)
      run = connection.integration_import_runs.create!(organization:, provider: :aryeo,
                                                       listing_start_date: Date.new(2026, 7, 3))

      described_class.new.up
      IntegrationImportRun.reset_column_information
      @migrated_run = IntegrationImportRun.find(run.id)

      example.run
      raise ActiveRecord::Rollback
    end
  end

  it "renames the column and preserves existing import dates" do
    expect(@migrated_run.import_start_date).to eq(Date.new(2026, 7, 3))
    expect(IntegrationImportRun.column_names).to include("import_start_date")
    expect(IntegrationImportRun.column_names).not_to include("listing_start_date")
  end
end
