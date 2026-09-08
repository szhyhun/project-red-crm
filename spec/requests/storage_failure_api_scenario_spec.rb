require "rails_helper"
require "stringio"
require "tempfile"
require "aws-sdk-s3"

RSpec.describe "Storage failure API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Storage failure agency", slug: "storage-failure-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Storage manager", email: "storage-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:participant) do
    User.create!(organization:, name: "Storage participant", email: "storage-participant@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Storage client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "12 Storage Street") }
  let!(:conversation) do
    Conversation.create!(organization:, kind: :internal, subject: "Storage failures").tap do |record|
      record.conversation_memberships.create!(user: manager, role: :manager)
      record.conversation_memberships.create!(user: participant, role: :participant)
    end
  end
  let!(:message) { conversation.messages.create!(author: manager, body: "Upload target") }
  let!(:task) { organization.default_board.workflow_tasks.create!(organization:, listing:, title: "Attachment target") }
  let(:s3_client) { instance_double(Aws::S3::Client) }
  let(:provider_error) { Aws::S3::Errors::ServiceError.new("PutObject", "bucket unavailable") }

  before do
    allow(s3_client).to receive(:put_object).and_raise(provider_error)
    sign_in participant
  end

  it "returns a controlled chat upload error when S3 rejects the object" do
    allow(ConversationStorage).to receive(:s3?).and_return(true)
    allow(ConversationStorage).to receive(:chat_media_bucket).and_return("chat-bucket")
    allow(ConversationStorage).to receive(:s3_client).and_return(s3_client)
    allow(ConversationStorage).to receive(:delete)
    upload = tempfile("chat-failure", "chat bytes")

    post "/api/v1/conversations/#{conversation.id}/messages/#{message.id}/attachments", params: {
      file: Rack::Test::UploadedFile.new(upload.path, "image/jpeg", true, original_filename: "chat.jpg")
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq("error" => "upload_failed")
    expect(message.conversation_attachments.order(:id).last).to have_attributes(status: "failed")
  ensure
    upload&.close!
  end

  it "returns a controlled board upload error when S3 rejects the object" do
    sign_out participant
    sign_in manager
    allow(BoardStorage).to receive(:s3?).and_return(true)
    allow(BoardStorage).to receive(:board_media_bucket).and_return("board-bucket")
    allow(BoardStorage).to receive(:s3_client).and_return(s3_client)
    allow(BoardStorage).to receive(:delete)
    upload = tempfile("board-failure", "board bytes")

    post "/api/v1/workflow_tasks/#{task.id}/attachments", params: {
      file: Rack::Test::UploadedFile.new(upload.path, "image/jpeg", true, original_filename: "board.jpg")
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq("error" => "upload_failed")
    expect(task.board_attachments.order(:id).last).to have_attributes(status: "failed")
  ensure
    upload&.close!
  end

  it "returns a controlled listing upload error when S3 rejects the object" do
    allow(DeliveryStorage).to receive(:s3?).and_return(true)
    allow(DeliveryStorage).to receive(:media_bucket).and_return("listing-bucket")
    allow(DeliveryStorage).to receive(:s3_client).and_return(s3_client)
    allow(DeliveryStorage).to receive(:delete)
    allow(MediaAssets::VerifyUploadJob).to receive(:perform_later)
    upload = tempfile("listing-failure", "listing bytes")

    post "/api/v1/media_assets/upload", params: {
      listing_id: listing.id,
      file: Rack::Test::UploadedFile.new(upload.path, "image/jpeg", true, original_filename: "listing.jpg")
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq("error" => "upload_failed")
    expect(listing.media_assets.order(:id).last).to have_attributes(status: "failed")
  ensure
    upload&.close!
  end

  private

  def tempfile(prefix, contents)
    file = Tempfile.new([ prefix, ".jpg" ])
    file.binmode
    file.write(contents)
    file.rewind
    file
  end
end
