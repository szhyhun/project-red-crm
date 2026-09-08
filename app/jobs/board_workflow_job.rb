class BoardWorkflowJob < ApplicationJob
  queue_as :workflows

  def perform(run_id)
    run = BoardWorkflowRun.find(run_id)
    Workflows::Runner.new(run:).call
  end
end
