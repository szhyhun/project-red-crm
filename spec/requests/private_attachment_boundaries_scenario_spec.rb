require "rails_helper"
require "tempfile"

RSpec.describe "Private attachment storage boundaries", type: :request do
  let!(:organization) { Organization.create!(name: "Attachment boundary agency", slug: "attachment-boundary-agency") }
  let!(:editor) do
    User.create!(organization:, name: "Boundary editor", email: "boundary-editor@example.test",
                password: "long-enough-password", role: :production_staff)
  end
  let!(:outsider) do
    User.create!(organization:, name: "Boundary outsider", email: "boundary-outsider@example.test",
                password: "long-enough-password", role: :production_staff)
  end
  let!(:conversation) do
    Conversation.create!(organization:, kind: :internal, subject: "Boundary chat").tap do |record|
      record.conversation_memberships.create!(user: editor, role: :participant)
    end
  end
  let!(:message) { conversation.messages.create!(author: editor, body: "Private files") }
  let!(:board) do
    organization.boards.create!(
      name: "Boundary board",
      kind: "internal",
      visibility: "restricted",
      requires_listing: false,
      client_visible: false,
      position: 1
    ).tap do |record|
      WorkflowColumn::DEFAULTS.each { |attributes| record.workflow_columns.create!(attributes.merge(organization:)) }
      record.board_memberships.create!(member: editor, access: "contributor")
    end
  end
  let!(:task) { board.workflow_tasks.create!(organization:, title: "Private board task", status: "todo") }
  let!(:chat_attachment) do
    conversation.conversation_attachments.create!(
      organization:,
      message:,
      uploaded_by: editor,
      status: :ready,
      storage_key: "organizations/#{organization.id}/conversations/#{conversation.id}/chat.txt",
      filename: "chat.txt",
      content_type: "text/plain",
      byte_size: 9
    )
  end
  let!(:board_attachment) do
    task.board_attachments.create!(
      organization:,
      board:,
      uploaded_by: editor,
      status: :ready,
      storage_key: "organizations/#{organization.id}/boards/#{board.id}/tasks/#{task.id}/board.txt",
      filename: "board.txt",
      content_type: "text/plain",
      byte_size: 10
    )
  end

  it "keeps both private serializers on API routes and in separate storage namespaces" do
    expect(chat_attachment.storage_key).to include("/conversations/#{conversation.id}/")
    expect(board_attachment.storage_key).to include("/boards/#{board.id}/tasks/#{task.id}/")

    serialized_chat = ConversationAttachment.serialize(chat_attachment)
    serialized_board = BoardAttachment.serialize(board_attachment)

    expect(serialized_chat).to include(
      preview_path: "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{chat_attachment.id}/preview",
      download_path: "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{chat_attachment.id}/download"
    )
    expect(serialized_board).to include(
      preview_path: "/api/v1/workflow_tasks/#{task.id}/attachments/#{board_attachment.id}/preview",
      download_path: "/api/v1/workflow_tasks/#{task.id}/attachments/#{board_attachment.id}/download"
    )
    expect(serialized_chat).not_to have_key(:storage_key)
    expect(serialized_board).not_to have_key(:storage_key)
    expect(serialized_chat[:preview_path]).not_to include("board_media")
    expect(serialized_board[:preview_path]).not_to include("chat_media")
  end

  it "streams chat and board files through their authorized API origins" do
    chat_file = Tempfile.new([ "chat-boundary", ".txt" ])
    chat_file.write("chat data")
    chat_file.rewind
    board_file = Tempfile.new([ "board-boundary", ".txt" ])
    board_file.write("board data")
    board_file.rewind
    allow(ConversationStorage).to receive(:s3?).and_return(false)
    allow(BoardStorage).to receive(:s3?).and_return(false)
    allow(ConversationStorage).to receive(:path_for).with(chat_attachment.storage_key).and_return(chat_file.path)
    allow(BoardStorage).to receive(:path_for).with(board_attachment.storage_key).and_return(board_file.path)

    sign_in editor
    get "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{chat_attachment.id}/preview"
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("chat data")
    expect(response.media_type).to eq("text/plain")

    get "/api/v1/workflow_tasks/#{task.id}/attachments/#{board_attachment.id}/preview"
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("board data")
    expect(response.media_type).to eq("text/plain")
  ensure
    chat_file&.close!
    board_file&.close!
  end

  it "denies the same internal user when they are outside either private parent" do
    sign_in outsider

    get "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{chat_attachment.id}/download"
    expect(response).to have_http_status(:not_found)

    get "/api/v1/workflow_tasks/#{task.id}/attachments/#{board_attachment.id}/download"
    expect(response).to have_http_status(:not_found)
  end
end
