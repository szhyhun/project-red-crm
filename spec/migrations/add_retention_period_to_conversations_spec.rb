require "rails_helper"
require Rails.root.join("db/migrate/20260907030000_add_retention_period_to_conversations").to_s

RSpec.describe AddRetentionPeriodToConversations, type: :migration do
  around do |example|
    ActiveRecord::Base.connection.transaction(requires_new: true) do
      organization = Organization.create!(name: "Migration Org", slug: "migration-conversation-retention")
      conversation = Conversation.create!(organization:, kind: :internal, subject: "Existing room", retention_period: :six_months)

      described_class.new.down
      Conversation.reset_column_information
      described_class.new.up
      Conversation.reset_column_information
      @migrated_conversation = Conversation.find(conversation.id)

      example.run
      raise ActiveRecord::Rollback
    end
  end

  it "backfills existing conversations to the default retention period" do
    expect(@migrated_conversation.retention_period).to eq("two_months")
    expect(Conversation.column_names).to include("retention_period")
    expect(Conversation.retention_periods.keys).to contain_exactly("two_months", "six_months", "one_year", "forever")
  end
end
