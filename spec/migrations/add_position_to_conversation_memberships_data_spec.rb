require "rails_helper"
require Rails.root.join("db/migrate/20260910100000_add_position_to_conversation_memberships").to_s

RSpec.describe AddPositionToConversationMemberships, type: :migration do
  around do |example|
    ActiveRecord::Base.connection.transaction(requires_new: true) do
      organization = Organization.create!(name: "Conversation order migration", slug: "conversation-order-migration")
      manager = User.create!(organization:, name: "Order manager", email: "order-migration-manager@example.test",
                             password: "long-enough-password", role: :manager)
      first = Conversation.create!(organization:, kind: :internal, subject: "First room")
      second = Conversation.create!(organization:, kind: :internal, subject: "Second room")
      customer = Conversation.create!(organization:, kind: :client,
                                      client_account: ClientAccount.create!(organization:, name: "Customer", kind: :agent),
                                      subject: "Customer room")
      first.conversation_memberships.create!(user: manager)
      second.conversation_memberships.create!(user: manager)
      customer.conversation_memberships.create!(user: manager)

      described_class.new.down
      ConversationMembership.reset_column_information
      described_class.new.up
      ConversationMembership.reset_column_information
      @migrated_memberships = ConversationMembership.where(user: manager).index_by(&:conversation_id)

      example.run
      raise ActiveRecord::Rollback
    end
  end

  it "assigns stable positions to existing team memberships without treating customer rooms as team order" do
    expect(@migrated_memberships.fetch(@migrated_memberships.keys.min).position).to eq(0)
    expect(@migrated_memberships.values.map(&:position)).to include(0, 1)
    expect(@migrated_memberships.values.find { |membership| membership.conversation.client? }.position).to eq(0)
    expect(ConversationMembership.column_names).to include("position")
  end
end
