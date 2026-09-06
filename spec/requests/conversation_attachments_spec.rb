require "rails_helper"
require "tempfile"

RSpec.describe "Conversation attachments", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-chat-attachments") }
  let!(:manager) do
    User.create!(organization:, name: "Manager", email: "chat-attachment-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:participant) do
    User.create!(organization:, name: "Participant", email: "chat-attachment-participant@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:outsider) do
    User.create!(organization:, name: "Outsider", email: "chat-attachment-outsider@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:conversation) do
    Conversation.create!(organization:, kind: :internal, subject: "Private production room").tap do |record|
      record.conversation_memberships.create!(user: manager, role: :manager)
      record.conversation_memberships.create!(user: participant)
    end
  end
  let!(:message) { conversation.messages.create!(author: manager, body: "Reference files") }

  it "keeps a private chat attachment out of a non-member's reach" do
    attachment = conversation.conversation_attachments.create!(
      organization:, message:, uploaded_by: manager, status: :ready,
      storage_key: "organizations/#{organization.id}/conversations/#{conversation.id}/private.txt",
      filename: "private.txt", content_type: "text/plain", byte_size: 5
    )

    sign_in outsider
    get "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{attachment.id}/download"

    expect(response).to have_http_status(:not_found)
  end

  it "uploads a file and returns authorized API routes without its storage key" do
    upload = Tempfile.new([ "chat-notes", ".txt" ])
    upload.write("notes")
    upload.rewind
    allow(ConversationStorage).to receive(:write)

    sign_in participant
    post "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments",
         params: { files: [ Rack::Test::UploadedFile.new(upload.path, "text/plain", true, original_filename: "chat-notes.txt") ] }

    expect(response).to have_http_status(:created)
    attachment = JSON.parse(response.body).fetch("conversation_attachments").first
    expect(attachment).to include("filename" => "chat-notes.txt", "status" => "ready")
    expect(attachment).not_to have_key("storage_key")
    expect(attachment.fetch("preview_path")).to include("/preview")
  ensure
    upload&.close!
  end

  it "rejects SVG uploads before they reach private storage" do
    upload = Tempfile.new([ "unsafe", ".svg" ])
    upload.write("<svg><script>alert(1)</script></svg>")
    upload.rewind
    sign_in participant

    expect do
      post "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments",
           params: { files: [ Rack::Test::UploadedFile.new(upload.path, "image/svg+xml", true, original_filename: "unsafe.svg") ] }
    end.not_to change(ConversationAttachment, :count)

    expect(response).to have_http_status(:unprocessable_entity)
  ensure
    upload&.close!
  end

  it "streams an S3 preview through the authorized API origin" do
    attachment = conversation.conversation_attachments.create!(
      organization:, message:, uploaded_by: manager, status: :ready,
      storage_key: "organizations/#{organization.id}/conversations/#{conversation.id}/preview.png",
      filename: "preview.png", content_type: "image/png", byte_size: 5
    )
    allow(ConversationStorage).to receive(:s3?).and_return(true)
    allow(ConversationStorage).to receive(:exist?).with(attachment.storage_key).and_return(true)
    allow(ConversationStorage).to receive(:stream).with(attachment.storage_key).and_return([ "image" ])

    sign_in participant
    get "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{attachment.id}/preview"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["Content-Disposition"]).to include("inline")
    expect(response.body).to eq("image")
  end

  it "does not render a legacy HTML attachment inline" do
    attachment = conversation.conversation_attachments.build(
      organization:, message:, uploaded_by: manager, status: :ready,
      storage_key: "organizations/#{organization.id}/conversations/#{conversation.id}/legacy.html",
      filename: "legacy.html", content_type: "text/html", byte_size: 5
    )
    attachment.save!(validate: false)
    allow(ConversationStorage).to receive(:s3?).and_return(true)
    allow(ConversationStorage).to receive(:exist?).with(attachment.storage_key).and_return(true)
    allow(ConversationStorage).to receive(:stream).with(attachment.storage_key).and_return([ "<p>x</p>" ])

    sign_in participant
    get "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{attachment.id}/preview"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/octet-stream")
    expect(response.headers["Content-Disposition"]).to include("attachment")
  end
end
