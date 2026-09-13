module Workflows
  class ExecuteRun < ApplicationInteractor
    def call
      run = context.fetch(:run)
      return context.set(:run, run) if run.succeeded? || run.succeeded_with_warnings?

      workflow = run.board_workflow
      scope = ActionScope.new(run:)
      run.update!(status: :running, started_at: Time.current, error: nil)
      warnings = []

      workflow.actions.ordered.each_with_index do |action, position|
        execute_action(run:, scope:, action:, position:, warnings:)
      end

      run.update!(status: warnings.empty? ? :succeeded : :succeeded_with_warnings,
                  error: warnings.join("; ").presence, completed_at: Time.current)
      context.set(:run, run).set(:warnings, warnings)
    rescue StandardError => error
      Rails.logger.error("Board workflow run #{run.id} failed: #{error.class}: #{error.message}")
      run.reload.update!(status: :failed, error: "#{error.class}: #{error.message}", completed_at: Time.current) unless run.failed?
      raise
    end

    private

    def execute_action(run:, scope:, action:, position:, warnings:)
      step = run.steps.find_or_initialize_by(board_workflow_action: action)
      step.update!(status: :running, position:, input: action.configuration)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = ExecuteAction.call(context: ApplicationInteractor::Context.new(action:, scope:))
      duration_ms = elapsed_milliseconds(started_at)
      record_step(run, action, result, duration_ms)

      if result.failure?
        step.update!(status: :failed, error: "#{result.failure.code}: #{result.failure.message}")
        raise result.failure.original_error || result.failure
      end

      output = result[:output] || {}
      step.update!(status: output[:skipped] ? :skipped : :succeeded, output: output.except(:skipped))
      warnings << output[:warning] if output[:warning]
    rescue StandardError => error
      step.update!(status: :failed, error: "#{error.class}: #{error.message}")
      raise
    end

    def record_step(run, action, result, duration_ms)
      run.metadata = run.metadata.merge(
        "last_interactor_step" => {
          "action_id" => action.id,
          "action_type" => action.action_type,
          "status" => result.failure? ? "failed" : "succeeded",
          "duration_ms" => duration_ms,
          "error_code" => result.failure&.code
        }.compact
      )
      run.save! if run.changed?
    end

    def elapsed_milliseconds(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end
  end
end
