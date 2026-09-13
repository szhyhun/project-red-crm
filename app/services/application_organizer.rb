class ApplicationOrganizer < ApplicationInteractor
  class << self
    def organize(*interactors)
      @interactors = interactors.freeze
    end

    def interactors
      @interactors || []
    end
  end

  def call
    self.class.interactors.each do |interactor|
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = interactor.call(context:)
      context.record_step(
        interactor.name,
        status: result.failure? ? "failed" : "succeeded",
        duration_ms: elapsed_milliseconds(started_at),
        error: result.failure
      )
      return context if result.failure?
    rescue StandardError => error
      context.record_step(
        interactor.name,
        status: "failed",
        duration_ms: elapsed_milliseconds(started_at),
        error: Failure.new(code: "unhandled_error", message: error.message, original_error: error)
      )
      raise
    end

    context
  end

  private

  def elapsed_milliseconds(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  end
end
