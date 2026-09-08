require "rails_helper"

RSpec.describe BoardWorkflowJob do
  it "delegates a queued run to the workflow runner" do
    run = instance_double(BoardWorkflowRun, id: 42)
    allow(BoardWorkflowRun).to receive(:find).with(42).and_return(run)
    runner = instance_double(Workflows::Runner)
    allow(Workflows::Runner).to receive(:new).with(run:).and_return(runner)
    expect(runner).to receive(:call)

    described_class.perform_now(42)
  end

  it "uses the workflows queue" do
    expect(described_class.queue_name).to eq("workflows")
  end
end
