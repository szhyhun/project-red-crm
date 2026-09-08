require "rails_helper"
require "tempfile"

RSpec.describe "conversation message API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Message scenario agency", slug: "message-api-scenario") }
  let!(:author) do
    User.create!(organization:, name: "Scenario author", email: "message-scenario-author@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:participant) do
    User.create!(organization:, name: "Scenario participant", email: "message-scenario-participant@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:conversation) do
    Conversation.create!(organization:, kind: :internal, subject: "Scenario room").tap do |record|
      record.conversation_memberships.create!(user: author, role: :manager)
      record.conversation_memberships.create!(user: participant, role: :participant)
    end
  end

  before do
    allow(Conversations::NotifyJob).to receive(:perform_later)
    sign_in author
  end

  it "persists a message, attaches a file, and returns authorized media routes when reopened" do
    post "/api/v1/conversations/#{conversation.id}/messages", params: {
      message: { body: "The final files are ready for review." }
    }

    expect(response).to have_http_status(:created)
    message = Message.find(response.parsed_body.dig("message", "id"))

    upload = Tempfile.new([ "scenario-attachment", ".jpg" ])
    upload.write("image bytes")
    upload.rewind
    allow(ConversationStorage).to receive(:write)

    post "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments", params: {
      files: [ Rack::Test::UploadedFile.new(upload.path, "image/jpeg", true, original_filename: "final.jpg") ]
    }

    expect(response).to have_http_status(:created)
    attachment = message.conversation_attachments.sole
    serialized_attachment = response.parsed_body.fetch("conversation_attachments").sole
    expect(serialized_attachment).to include(
      "id" => attachment.id,
      "status" => "ready",
      "preview_path" => "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{attachment.id}/preview",
      "download_path" => "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments/#{attachment.id}/download"
    )
    expect(serialized_attachment).not_to have_key("storage_key")

    get "/api/v1/conversations/#{conversation.id}"

    expect(response).to have_http_status(:ok)
    reopened_message = response.parsed_body.dig("conversation", "messages").sole
    expect(reopened_message).to include("id" => message.id, "body" => "The final files are ready for review.")
    expect(reopened_message.fetch("attachments")).to contain_exactly(
      hash_including("id" => attachment.id, "filename" => "final.jpg")
    )
  ensure
    upload&.close!
  end
end
