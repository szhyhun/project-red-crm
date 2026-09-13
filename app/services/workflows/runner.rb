module Workflows
  # Compatibility adapter for callers that still instantiate Runner directly.
  # New queue entry points use ExecuteRun; this adapter can be removed after
  # downstream callers migrate.
  class Runner
    def initialize(run:)
      @run = run
    end

    def call
      result = ExecuteRun.call(run: @run)
      raise result.failure.original_error || result.failure if result.failure?

      @run.reload
    end
  end
end
