require "rails_helper"

RSpec.describe ApplicationOrganizer do
  it "records reusable step outcomes and stops at the first failure" do
    first_step = Class.new(ApplicationInteractor) do
      def call
        context.set(:value, "first")
      end
    end
    failing_step = Class.new(ApplicationInteractor) do
      def call
        context.fail!(code: "expected_failure", message: "The second step failed")
      end
    end
    unreachable_step = Class.new(ApplicationInteractor) do
      def call
        context.set(:value, "unreachable")
      end
    end
    stub_const("FirstStep", first_step)
    stub_const("FailingStep", failing_step)
    stub_const("UnreachableStep", unreachable_step)

    organizer = Class.new(ApplicationOrganizer)
    organizer.organize(FirstStep, FailingStep, UnreachableStep)

    result = organizer.call

    expect(result).to be_failure
    expect(result[:value]).to eq("first")
    expect(result.failure.code).to eq("expected_failure")
    expect(result.steps.map { |step| step[:status] }).to eq(%w[succeeded failed])
  end
end
