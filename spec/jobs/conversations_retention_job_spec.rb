require "rails_helper"

RSpec.describe Conversations::RetentionJob do
  it "uses the maintenance queue" do
    expect(described_class.queue_name).to eq("maintenance")
  end

  it "runs the shared retention service when Resque Scheduler invokes it" do
    result = Conversations::Retention::Result.new(messages_deleted: 2, attachments_deleted: 1, failures: 0)
    allow(Conversations::Retention).to receive(:call).and_return(result)

    described_class.perform_now

    expect(Conversations::Retention).to have_received(:call)
  end

  it "keeps the class-level Resque entry point on Active Job" do
    expect(described_class).to receive(:perform_now)

    described_class.perform
  end
end
