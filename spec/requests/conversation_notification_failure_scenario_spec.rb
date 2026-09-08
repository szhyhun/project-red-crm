require "rails_helper"

RSpec.describe "Conversation notification failure API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Notification failure agency", slug: "notification-failure-agency") }
  let!(:author) do
    User.create!(organization:, name: "Notification author", email: "notification-author@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:participant) do
    User.create!(organization:, name: "Notification participant", email: "notification-participant@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:conversation) do
    Conversation.create!(organization:, kind: :internal, subject: "Notification failure room").tap do |record|
      record.conversation_memberships.create!(user: author, role: :manager)
      record.conversation_memberships.create!(user: participant, role: :participant)
    end
  end

  before { sign_in author }

  it "returns the saved message even when the notification queue is unavailable" do
    allow(Conversations::NotifyJob).to receive(:perform_later)
      .and_raise(StandardError, "Redis is temporarily unavailable")

    expect {
      post "/api/v1/conversations/#{conversation.id}/messages", params: {
        message: { body: "The message must not disappear when notifications fail." }
      }
    }.to change(Message, :count).by(1)

    expect(response).to have_http_status(:created)
    message = conversation.messages.order(:id).last
    expect(message).to have_attributes(author: author,
                                       body: "The message must not disappear when notifications fail.")
    expect(Conversations::NotifyJob).to have_received(:perform_later).with(message.id)

    get "/api/v1/conversations/#{conversation.id}"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("conversation", "messages")).to include(
      include("id" => message.id, "body" => message.body)
    )
  end
end
