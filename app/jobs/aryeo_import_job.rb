class AryeoImportJob < ApplicationJob
  queue_as :integrations

  def perform(import_run_id)
    run = IntegrationImportRun.find(import_run_id)
    result = Aryeo::RunImport.call(run:)
    return if result.success?

    Rails.logger.error("Aryeo import #{import_run_id} failed: #{result.failure.class}: #{result.failure.message}")
    raise result.failure.original_error || result.failure
  end
end
