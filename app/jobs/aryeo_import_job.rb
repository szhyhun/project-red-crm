class AryeoImportJob < ApplicationJob
  queue_as :integrations

  def perform(import_run_id, listing_limit: nil, skip_resources: [])
    run = IntegrationImportRun.find(import_run_id)
    Aryeo::Importer.new(run:, listing_limit:, skip_resources:).call
  end
end
