class BoardWorkflowJob < ApplicationJob
  queue_as :workflows

  def perform(run_id)
    run = BoardWorkflowRun.find(run_id)
    result = Workflows::ExecuteRun.call(run:)
    raise result.failure.original_error || result.failure if result.failure?
  end
end
