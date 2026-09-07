require "rails_helper"

RSpec.describe Conversations::RetentionJob do
  it "exposes a Resque-compatible class-level entry point" do
    allow(described_class).to receive(:perform_now)

    described_class.perform

    expect(described_class).to have_received(:perform_now)
  end
end
