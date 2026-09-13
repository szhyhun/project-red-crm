module Aryeo
  class ImportWatchdogJob < ApplicationJob
    queue_as :maintenance

    # Resque Scheduler invokes jobs through Resque's class-level perform API.
    # Keep the scheduled entry on Active Job so manual runs use the same path.
    def self.perform
      perform_now
    end

    def perform(at = Time.current)
      IntegrationImportRun.where(status: :running).find_each do |run|
        next unless run.stale?(at:)

        message = "Aryeo import worker heartbeat expired at #{at.iso8601}"
        run.mark_failed!(message, at:)
        reconnect_connection_if_idle(run.integration_connection)
        Rails.logger.error("Aryeo import #{run.id} marked failed: #{message}")
      end
    end

    private

    def reconnect_connection_if_idle(connection)
      return unless connection.status_importing?
      return if connection.integration_import_runs.running.exists?

      connection.update!(status: :connected)
    end
  end
end
