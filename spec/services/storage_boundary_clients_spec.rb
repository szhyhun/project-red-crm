require "rails_helper"
require "fileutils"
require "stringio"

RSpec.describe "storage boundary clients" do
  let(:s3_client) { instance_double(Aws::S3::Client) }

  it "writes chat attachments to the dedicated chat bucket" do
    allow(ConversationStorage).to receive(:chat_media_bucket).and_return("projectred-chat-media")
    allow(ConversationStorage).to receive(:s3_client).and_return(s3_client)
    upload = StringIO.new("chat bytes")

    expect(s3_client).to receive(:put_object).with(
      bucket: "projectred-chat-media", key: "organizations/1/conversations/2/messages/3/file.jpg",
      body: upload, content_type: "image/jpeg"
    ).and_return(:stored)

    expect(ConversationStorage.write(
      upload:, key: "organizations/1/conversations/2/messages/3/file.jpg", content_type: "image/jpeg"
    )).to eq(:stored)
  end

  it "writes board attachments to the board bucket instead of the delivery bucket" do
    allow(BoardStorage).to receive(:board_media_bucket).and_return("projectred-board-media")
    allow(BoardStorage).to receive(:s3_client).and_return(s3_client)
    upload = StringIO.new("board bytes")

    expect(s3_client).to receive(:put_object).with(
      bucket: "projectred-board-media", key: "organizations/1/boards/2/tasks/3/file.pdf",
      body: upload, content_type: "application/pdf"
    ).and_return(:stored)

    expect(BoardStorage.write(
      upload:, key: "organizations/1/boards/2/tasks/3/file.pdf", content_type: "application/pdf"
    )).to eq(:stored)
  end

  it "writes listing delivery media to the listing media bucket" do
    allow(DeliveryStorage).to receive(:media_bucket).and_return("projectred-listing-media")
    allow(DeliveryStorage).to receive(:s3_client).and_return(s3_client)
    upload = StringIO.new("delivery bytes")

    expect(s3_client).to receive(:put_object).with(
      bucket: "projectred-listing-media", key: "organizations/1/listings/2/file.jpg",
      body: upload, content_type: "image/jpeg"
    ).and_return(:stored)

    expect(DeliveryStorage.write(
      upload:, key: "organizations/1/listings/2/file.jpg", content_type: "image/jpeg"
    )).to eq(:stored)
  end

  it "round-trips chat objects through the local private storage root" do
    root = Pathname.new(Dir.mktmpdir("projectred-chat-storage"))
    stub_const("ConversationStorage::ROOT", root)
    key = "organizations/1/conversations/2/messages/3/asset.txt"

    ConversationStorage.write(upload: StringIO.new("hello"), key:)

    expect(ConversationStorage.exist?(key)).to be(true)
    expect(ConversationStorage.enum_for(:stream, key).to_a.join).to eq("hello")

    ConversationStorage.delete(key)

    expect(ConversationStorage.exist?(key)).to be(false)
  ensure
    FileUtils.remove_entry(root) if root&.directory?
  end

  it "round-trips board objects through a separate local storage root" do
    root = Pathname.new(Dir.mktmpdir("projectred-board-storage"))
    stub_const("BoardStorage::ROOT", root)
    key = "organizations/1/boards/2/tasks/3/asset.txt"

    BoardStorage.write(upload: StringIO.new("hello"), key:)

    expect(BoardStorage.exist?(key)).to be(true)
    expect(BoardStorage.enum_for(:stream, key).to_a.join).to eq("hello")

    BoardStorage.delete(key)

    expect(BoardStorage.exist?(key)).to be(false)
  ensure
    FileUtils.remove_entry(root) if root&.directory?
  end
end
