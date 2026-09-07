require "rails_helper"

RSpec.describe Conversation do
  let(:now) { Time.zone.parse("2026-09-07 12:00:00") }

  it "defaults to two months and exposes only the supported retention periods" do
    conversation = described_class.new

    expect(conversation.retention_period).to eq("two_months")
    expect(described_class.retention_periods.keys).to contain_exactly("two_months", "six_months", "one_year", "forever")
    expect(conversation.retention_days).to eq(60)
    expect(described_class.new(retention_period: :six_months).retention_days).to eq(180)
    expect(described_class.new(retention_period: :one_year).retention_days).to eq(365)
  end

  it "calculates a cutoff for finite periods and no cutoff for forever" do
    expect(described_class.new(retention_period: :two_months).retention_cutoff(now)).to eq(60.days.ago(now))
    expect(described_class.new(retention_period: :forever).retention_cutoff(now)).to be_nil
  end
end
