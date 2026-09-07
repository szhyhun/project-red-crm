require "rails_helper"

RSpec.describe "Conversation messages", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-messages") }
  let!(:author) do
    User.create!(organization:, name: "Morgan", email: "messages-author@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:conversation) do
    Conversation.create!(organization:, kind: :internal, subject: "Work chat").tap do |record|
      record.conversation_memberships.create!(user: author)
    end
  end

  before { sign_in author }

  it "queues the live notification rather than broadcasting inside the request" do
    expect {
      post "/api/v1/conversations/#{conversation.id}/messages", params: { message: { body: "files are up" } }
    }.to have_enqueued_job(Conversations::NotifyJob)

    expect(response).to have_http_status(:created)
  end

  # Telling other people is a side effect of sending. Broadcasting inline put a
  # Redis round trip inside a user-facing POST, so an unreachable cable adapter
  # hung the request and then failed it -- after the message had already saved.
  it "still sends the message when the notification cannot be queued" do
    allow(Conversations::NotifyJob).to receive(:perform_later).and_raise(Redis::CannotConnectError, "boom")

    post "/api/v1/conversations/#{conversation.id}/messages", params: { message: { body: "still sends" } }

    expect(response).to have_http_status(:created)
    expect(conversation.messages.reload.last.body).to eq("still sends")
  end
end
