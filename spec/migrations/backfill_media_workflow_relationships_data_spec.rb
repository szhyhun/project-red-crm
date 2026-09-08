require "rails_helper"
require_relative "../../db/migrate/20260907041000_backfill_media_workflow_relationships"

RSpec.describe BackfillMediaWorkflowRelationships, type: :migration do
  let!(:organization) { Organization.create!(name: "Migration data agency", slug: "migration-data-agency") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Migration data client", kind: :agent) }
  let!(:first_listing) { Listing.create!(organization:, client_account:, address_line_1: "First Migration Street") }
  let!(:second_listing) { Listing.create!(organization:, client_account:, address_line_1: "Second Migration Street") }
  let!(:manager) do
    User.create!(organization:, name: "Migration manager", email: "migration-data-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:producer) do
    User.create!(organization:, name: "Migration producer", email: "migration-data-producer@example.test",
                 password: "long-enough-password", role: :production_staff)
  end

  it "merges duplicate account conversations without losing context, messages, attachments, or read state" do
    ActiveRecord::Base.connection.remove_index(:conversations, name: "index_one_client_conversation_per_account")
    keeper = Conversation.create!(organization:, client_account:, listing: first_listing, kind: :client,
                                  subject: "First listing thread")
    duplicate = Conversation.create!(organization:, client_account:, listing: second_listing, kind: :client,
                                     subject: "Second listing thread")
    keeper.conversation_memberships.create!(user: manager, role: :manager, last_read_at: 2.hours.ago)
    duplicate.conversation_memberships.create!(user: manager, role: :participant, last_read_at: 1.hour.ago)
    duplicate.conversation_memberships.create!(user: producer, role: :participant)

    created_at = 10.minutes.ago.change(usec: 0)
    message = duplicate.messages.create!(author: producer, body: "Keep this production update",
                                         created_at:, updated_at: created_at)
    attachment = duplicate.conversation_attachments.create!(
      organization:, conversation: duplicate, message:, uploaded_by: producer, status: :ready,
      storage_key: "organizations/#{organization.id}/conversations/#{duplicate.id}/update.jpg",
      filename: "update.jpg", content_type: "image/jpeg", byte_size: 5,
      created_at:, updated_at: created_at
    )

    described_class.new.up

    expect(Conversation.where(organization:, client_account:).count).to eq(1)
    expect(Conversation.find(keeper.id)).to have_attributes(listing_id: nil, last_message_at: created_at)
    expect(Conversation.exists?(duplicate.id)).to be(false)
    expect(message.reload).to have_attributes(conversation_id: keeper.id, listing_id: second_listing.id)
    expect(attachment.reload).to have_attributes(conversation_id: keeper.id, message_id: message.id)
    expect(keeper.reload.conversation_memberships.pluck(:user_id)).to contain_exactly(manager.id, producer.id)
    expect(keeper.conversation_memberships.find_by!(user: manager).last_read_at).to be_within(1.second).of(1.hour.ago)
    expect(ActiveRecord::Base.connection.indexes(:conversations).map(&:name)).to include(
      "index_one_client_conversation_per_account"
    )
  end
end
