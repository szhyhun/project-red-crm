require "rails_helper"
require "stringio"

RSpec.describe "storage provider failure contracts" do
  let(:s3_client) { instance_double(Aws::S3::Client) }
  let(:provider_error) { Aws::S3::Errors::ServiceError.new("PutObject", "bucket unavailable") }

  it "turns a chat bucket provider failure into the storage error handled by the API" do
    allow(ConversationStorage).to receive(:chat_media_bucket).and_return("chat-bucket")
    allow(ConversationStorage).to receive(:s3_client).and_return(s3_client)
    allow(s3_client).to receive(:put_object).and_raise(provider_error)

    expect {
      ConversationStorage.write(upload: StringIO.new("chat"), key: "chat/file.jpg", content_type: "image/jpeg")
    }.to raise_error(ConversationStorage::WriteError, "bucket unavailable")
  end

  it "turns a board bucket provider failure into the storage error handled by the API" do
    allow(BoardStorage).to receive(:board_media_bucket).and_return("board-bucket")
    allow(BoardStorage).to receive(:s3_client).and_return(s3_client)
    allow(s3_client).to receive(:put_object).and_raise(provider_error)

    expect {
      BoardStorage.write(upload: StringIO.new("board"), key: "board/file.jpg", content_type: "image/jpeg")
    }.to raise_error(BoardStorage::WriteError, "bucket unavailable")
  end

  it "turns a listing media bucket provider failure into the storage error handled by the API" do
    allow(DeliveryStorage).to receive(:media_bucket).and_return("listing-bucket")
    allow(DeliveryStorage).to receive(:s3_client).and_return(s3_client)
    allow(s3_client).to receive(:put_object).and_raise(provider_error)

    expect {
      DeliveryStorage.write(upload: StringIO.new("listing"), key: "listing/file.jpg", content_type: "image/jpeg")
    }.to raise_error(DeliveryStorage::WriteError, "bucket unavailable")
  end
end
