module Aryeo
  class FailStaleImports < ApplicationInteractor
    def call
      at = context.fetch(:at, Time.current)
      failed_run_ids = []

      IntegrationImportRun.where(status: :running).find_each do |run|
        next unless run.stale?(at:)

        message = "Aryeo import worker heartbeat expired at #{at.iso8601}"
        run.mark_failed!(message, at:)
        reconnect_connection_if_idle(run.integration_connection)
        Rails.logger.error("Aryeo import #{run.id} marked failed: #{message}")
        failed_run_ids << run.id
      end

      context.set(:failed_run_ids, failed_run_ids)
    end

    private

    def reconnect_connection_if_idle(connection)
      return unless connection.status_importing?
      return if connection.integration_import_runs.running.exists?

      connection.update!(status: :connected)
    end
  end
end
