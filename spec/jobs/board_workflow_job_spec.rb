require "rails_helper"

RSpec.describe BoardWorkflowJob do
  it "delegates a queued run to the workflow interactor" do
    run = instance_double(BoardWorkflowRun, id: 42)
    allow(BoardWorkflowRun).to receive(:find).with(42).and_return(run)
    result = ApplicationInteractor::Context.new(run:)
    allow(Workflows::ExecuteRun).to receive(:call).with(run:).and_return(result)
    expect(Workflows::ExecuteRun).to receive(:call).with(run:)

    described_class.perform_now(42)
  end

  it "uses the workflows queue" do
    expect(described_class.queue_name).to eq("workflows")
  end
end
