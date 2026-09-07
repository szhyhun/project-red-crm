require "rails_helper"

RSpec.describe "Conversation retention", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-chat-retention") }
  let!(:manager) do
    User.create!(organization:, name: "Morgan Manager", email: "retention-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:participant) do
    User.create!(organization:, name: "Parker Producer", email: "retention-participant@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:conversation) do
    Conversation.create!(organization:, kind: :internal, subject: "Retention room").tap do |record|
      record.conversation_memberships.create!(user: manager, role: :manager)
      record.conversation_memberships.create!(user: participant, role: :participant)
    end
  end

  it "does not let a participant change the conversation retention period" do
    sign_in participant

    patch "/api/v1/conversations/#{conversation.id}", params: { conversation: { retention_period: "forever" } }

    expect(response).to have_http_status(:forbidden)
    expect(conversation.reload.retention_period).to eq("two_months")
  end

  it "lets a conversation manager change and read the retention period" do
    sign_in manager

    patch "/api/v1/conversations/#{conversation.id}", params: { conversation: { retention_period: "six_months" } }

    expect(response).to have_http_status(:ok)
    expect(conversation.reload.retention_period).to eq("six_months")
    expect(JSON.parse(response.body).dig("conversation", "retention_period")).to eq("six_months")
  end

  it "rejects unsupported retention periods" do
    sign_in manager

    patch "/api/v1/conversations/#{conversation.id}", params: { conversation: { retention_period: "not_a_retention_period" } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(conversation.reload.retention_period).to eq("two_months")
  end
end
