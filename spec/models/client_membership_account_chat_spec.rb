require "rails_helper"

RSpec.describe ClientMembership, type: :model do
  let!(:organization) { Organization.create!(name: "Chat join agency", slug: "chat-join-agency") }
  let!(:account) { ClientAccount.create!(organization:, name: "Chat Team", kind: :team) }
  let!(:founder) { person("chat-founder", :client_admin) }
  let!(:founder_membership) { ClientMembership.create!(client_account: account, user: founder, role: :admin, status: :active) }
  let!(:chat) { organization.conversations.create!(kind: :client, client_account: account, subject: "Chat Team") }

  def person(handle, role)
    User.create!(organization:, name: handle.humanize, email: "#{handle}@example.test", password: "long-enough-password", role:)
  end

  it "does not add an invited admin, or a member who accepts, to the team's chat" do
    admin = person("chat-invited-admin", :client_admin)
    ClientMembership.create!(client_account: account, user: admin, role: :admin, status: :invited)
    member = person("chat-member", :client_member)
    ClientMembership.create!(client_account: account, user: member, role: :member, status: :invited).accept!

    expect(chat.users).not_to include(admin, member)
  end

  it "adds an admin to the team's chat when they accept, and a member when they are made an admin" do
    admin = person("chat-admin", :client_admin)
    ClientMembership.create!(client_account: account, user: admin, role: :admin, status: :invited).accept!
    member = person("chat-promoted", :client_member)
    membership = ClientMembership.create!(client_account: account, user: member, role: :member, status: :active)

    membership.update!(role: :admin)
    membership.update!(role: :member)
    membership.update!(role: :admin)

    expect(chat.conversation_memberships.where(user: [ admin, member ]).count).to eq(2)
  end

  it "adds a moved active admin to the destination team's existing chat" do
    destination = ClientAccount.create!(organization:, name: "Destination Team", kind: :team)
    destination_chat = organization.conversations.create!(kind: :client, client_account: destination, subject: "Destination")
    admin = person("chat-moved-admin", :client_admin)
    membership = ClientMembership.create!(client_account: account, user: admin, role: :admin, status: :active)

    membership.update!(client_account: destination)

    expect(destination_chat.users).to include(admin)
  end

  it "creates no chat for a team that has none" do
    chat.destroy!
    admin = person("chat-no-room", :client_admin)
    ClientMembership.create!(client_account: account, user: admin, role: :admin, status: :invited).accept!

    expect(Conversation.count).to eq(0)
  end
end
