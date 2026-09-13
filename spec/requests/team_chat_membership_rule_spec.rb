require "rails_helper"

RSpec.describe "Who is in a team's chat", type: :request do
  let!(:organization) { Organization.create!(name: "Chat rule agency", slug: "chat-rule-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Chat rule manager", email: "chat-rule-manager@example.test",
                 password: "long-enough-password", role: :organization_admin)
  end
  let!(:team) { ClientAccount.create!(organization:, name: "Chat Rule Team", kind: :team) }
  let!(:other_team) { ClientAccount.create!(organization:, name: "Other Chat Team", kind: :team) }
  let!(:admin) { customer("rule-admin", :admin, :active) }
  let!(:member) { customer("rule-member", :member, :active) }
  let!(:revoked_admin) { customer("rule-revoked", :admin, :revoked) }
  let!(:invited_admin) { customer("rule-invited", :admin, :invited) }
  let!(:outsider) { customer("rule-outsider", :admin, :active, other_team) }

  def customer(handle, role, status, account = team)
    User.create!(organization:, name: handle.humanize, email: "#{handle}@example.test", password: "long-enough-password",
                 role: role == :admin ? :client_admin : :client_member).tap do |user|
      ClientMembership.create!(client_account: account, user:, role:, status:)
    end
  end

  def open_chat(member_ids = [])
    post "/api/v1/conversations", params: {
      conversation: { kind: "client", client_account_id: team.id, subject: "Hello", member_ids: }
    }
  end

  it "refuses to put another team's customer into this team's chat" do
    sign_in manager
    open_chat([ outsider.id ])

    expect(response).to have_http_status(:unprocessable_content)
    expect(Conversation.count).to eq(0)
  end

  it "starts a team chat with its active admins only, and adds a member only by name" do
    sign_in manager

    open_chat
    expect(response).to have_http_status(:created)
    chat = Conversation.client.find_by!(client_account: team)
    expect(chat.users).to contain_exactly(manager, admin)

    chat.destroy!
    open_chat([ member.id ])
    expect(Conversation.client.find_by!(client_account: team).users).to contain_exactly(manager, admin, member)
  end
end
