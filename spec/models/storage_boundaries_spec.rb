require "rails_helper"

RSpec.describe "private media storage boundaries" do
  let!(:organization) { Organization.create!(name: "Storage agency", slug: "storage-boundaries") }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Storage client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "1 Storage Street") }
  let!(:board) { organization.default_board }
  let!(:task) { board.workflow_tasks.create!(organization:, listing:, title: "Storage task", status: "todo") }
  let!(:conversation) { Conversation.create!(organization:, kind: :internal, subject: "Storage chat") }
  let!(:author) do
    User.create!(organization:, name: "Storage author", email: "storage-author@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:message) { conversation.messages.create!(author:, body: "Storage message") }

  it "uses different namespaces for chat, board, and listing delivery objects" do
    chat_key = ConversationStorage.key_for(organization:, conversation:, message:, filename: "notes.txt")
    board_key = BoardStorage.key_for(organization:, board:, task:, filename: "notes.txt")
    delivery_key = DeliveryStorage.key_for(organization:, listing:, filename: "notes.txt")

    expect(chat_key).to start_with("organizations/#{organization.id}/conversations/")
    expect(board_key).to start_with("organizations/#{organization.id}/boards/")
    expect(delivery_key).to start_with("organizations/#{organization.id}/listings/")
    expect([ chat_key, board_key, delivery_key ].uniq.size).to eq(3)
  end

  it "rejects traversal outside each local storage root" do
    expect { ConversationStorage.path_for("../../config/database.yml") }.to raise_error(ConversationStorage::MissingFile)
    expect { BoardStorage.path_for("../../config/database.yml") }.to raise_error(BoardStorage::MissingFile)
    expect { DeliveryStorage.path_for("../../config/database.yml") }.to raise_error(DeliveryStorage::MissingFile)
  end

  it "serializes chat attachments with API routes instead of storage keys" do
    attachment = conversation.conversation_attachments.create!(
      organization:, message:, uploaded_by: author, status: :ready,
      storage_key: "organizations/#{organization.id}/conversations/private.txt",
      filename: "private.txt", content_type: "text/plain", byte_size: 5
    )

    serialized = ConversationAttachment.serialize(attachment)

    expect(serialized).not_to have_key("storage_key")
    expect(serialized.fetch(:preview_path)).to eq(
      "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{attachment.id}/preview"
    )
  end

  it "serializes board attachments with API routes and no CDN URL" do
    attachment = task.board_attachments.create!(
      organization:, board:, uploaded_by: author, status: :ready,
      storage_key: "organizations/#{organization.id}/boards/#{board.id}/tasks/#{task.id}/private.txt",
      filename: "private.txt", content_type: "text/plain", byte_size: 5
    )

    serialized = BoardAttachment.serialize(attachment)

    expect(serialized).to include(cdn_url: nil)
    expect(serialized).not_to have_key("storage_key")
    expect(serialized.fetch(:download_path)).to eq(
      "/api/v1/workflow_tasks/#{task.id}/attachments/#{attachment.id}/download"
    )
  end
end
