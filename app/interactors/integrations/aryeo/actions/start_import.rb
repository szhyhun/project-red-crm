module Integrations::Aryeo::Actions
  class StartImport < ApplicationInteractor
    def call
      run = context.fetch(:run)
      connection = run.integration_connection

      run.with_lock do
        return context.set(:skipped, true).set(:run, run) if run.terminal?

        now = Time.current
        run.update!(status: :running, phase: "starting", started_at: run.started_at || now, heartbeat_at: now)
      end
      connection.update!(status: :importing) unless connection.status_importing?

      context.set(:run, run).set(:connection, connection)
    end
  end
end
