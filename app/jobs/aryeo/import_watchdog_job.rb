module Aryeo
  class ImportWatchdogJob < ApplicationJob
    queue_as :maintenance

    # Resque Scheduler invokes jobs through Resque's class-level perform API.
    # Keep the scheduled entry on Active Job so manual runs use the same path.
    def self.perform
      perform_now
    end

    def perform(at = Time.current)
      Aryeo::FailStaleImports.call(at:)
    end
  end
end
