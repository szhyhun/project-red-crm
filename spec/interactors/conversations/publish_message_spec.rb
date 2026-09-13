require "rails_helper"

RSpec.describe Conversations::PublishMessage, type: :interactor do
  let!(:organization) { Organization.create!(name: "Publish message agency", slug: "publish-message-agency") }
  let!(:author) do
    User.create!(organization:, name: "Publish message author", email: "publish-message@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:conversation) { Conversation.create!(organization:, kind: :internal, subject: "Production notes") }
  let!(:asset) do
    MediaAsset.create!(organization:, uploaded_by: author, kind: :final, status: :ready,
                       storage_key: "publish-message/asset.jpg", filename: "asset.jpg",
                       content_type: "image/jpeg", byte_size: 12, customer_visible: true)
  end

  before do
    allow(Conversations::NotifyJob).to receive(:perform_later)
  end

  it "commits the message, references, timestamp, and notification as one action" do
    result = described_class.call(conversation:, author:, body: "The files are ready.", media_assets: [ asset ])

    expect(result).to be_success
    message = result.fetch(:message)
    expect(message).to have_attributes(conversation:, author:, body: "The files are ready.")
    expect(message.message_media_references.pluck(:media_asset_id)).to eq([ asset.id ])
    expect(conversation.reload.last_message_at).to eq(message.created_at)
    expect(Conversations::NotifyJob).to have_received(:perform_later).with(message.id)
  end

  it "keeps the committed message when the notification queue is unavailable" do
    allow(Conversations::NotifyJob).to receive(:perform_later).and_raise("Redis is unavailable")

    result = described_class.call(conversation:, author:, body: "Keep this message")

    expect(result).to be_success
    expect(conversation.messages.where(body: "Keep this message")).to exist
  end

  it "rolls back the message when a media reference crosses organizations" do
    foreign_organization = Organization.create!(name: "Other message agency", slug: "other-message-agency")
    foreign_asset = MediaAsset.create!(organization: foreign_organization, kind: :final, status: :ready,
                                       storage_key: "foreign/asset.jpg", filename: "foreign.jpg",
                                       content_type: "image/jpeg", byte_size: 12, customer_visible: true)

    result = described_class.call(conversation:, author:, body: "Do not attach that", media_assets: [ foreign_asset ])

    expect(result).to be_failure
    expect(result.failure.code).to eq("message_invalid")
    expect(conversation.reload.messages).to be_empty
    expect(conversation.reload.last_message_at).to be_nil
  end
end
