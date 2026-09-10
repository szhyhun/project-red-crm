require "rails_helper"

RSpec.describe "Conversation sidebar ordering API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Unread ordering agency", slug: "unread-ordering-agency") }
  let!(:manager) do
    User.create!(organization:, name: "Unread ordering manager", email: "unread-ordering-manager@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:teammate) do
    User.create!(organization:, name: "Unread ordering teammate", email: "unread-ordering-teammate@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:admin) do
    User.create!(organization:, name: "Unread ordering admin", email: "unread-ordering-admin@example.test",
                 password: "long-enough-password", role: :organization_admin)
  end

  before do
    allow(Conversations::NotifyJob).to receive(:perform_later)
    sign_in manager
  end

  it "keeps team conversations in their saved order regardless of unread state" do
    base_time = Time.zone.parse("2026-09-08 10:00:00")
    read_room, = create_room("Read room")
    unread_room, unread_membership = create_room("Unread room")

    create_message(read_room, author: manager, body: "My latest update", at: base_time + 5.hours)
    unread_message = create_message(unread_room, author: teammate, body: "Please review this", at: base_time + 2.hours)
    unread_membership.update_columns(last_read_at: base_time + 1.hour, updated_at: base_time + 1.hour)

    get "/api/v1/conversations"

    expect(response).to have_http_status(:ok)
    conversations = response.parsed_body.fetch("conversations")
    expect(conversations.map { |conversation| conversation.fetch("id") }.first(2)).to eq([ read_room.id, unread_room.id ])
    expect(conversations.find { |conversation| conversation.fetch("id") == unread_room.id }).to include(
      "unread_count" => 1,
      "last_unread_message_at" => unread_message.reload.created_at.utc.iso8601(3)
    )
  end

  it "does not change team order when messages arrive" do
    base_time = Time.zone.parse("2026-09-08 11:00:00")
    older_unread_room, older_membership = create_room("Older unread room")
    newer_unread_room, newer_membership = create_room("Newer unread room")

    older_unread = create_message(older_unread_room, author: teammate, body: "Earlier request", at: base_time + 2.hours)
    create_message(older_unread_room, author: manager, body: "My later reply", at: base_time + 8.hours)
    newer_unread = create_message(newer_unread_room, author: teammate, body: "Later request", at: base_time + 4.hours)
    older_membership.update_columns(last_read_at: base_time + 1.hour, updated_at: base_time + 1.hour)
    newer_membership.update_columns(last_read_at: base_time + 3.hours, updated_at: base_time + 3.hours)

    get "/api/v1/conversations"

    expect(response).to have_http_status(:ok)
    conversations = response.parsed_body.fetch("conversations")
    expect(conversations.map { |conversation| conversation.fetch("id") }.first(2)).to eq([ older_unread_room.id, newer_unread_room.id ])
    expect(conversations.find { |conversation| conversation["id"] == older_unread_room.id }).to include(
      "unread_count" => 1,
      "last_unread_message_at" => older_unread.reload.created_at.utc.iso8601(3)
    )
    expect(conversations.find { |conversation| conversation["id"] == newer_unread_room.id }).to include(
      "unread_count" => 1,
      "last_unread_message_at" => newer_unread.reload.created_at.utc.iso8601(3)
    )
  end

  it "persists a reordered team sidebar and rejects customer reordering" do
    first_room, = create_room("First team room")
    second_room, = create_room("Second team room")

    post "/api/v1/conversations/reorder", params: { conversation_ids: [ second_room.id, first_room.id ] }

    expect(response).to have_http_status(:ok)
    expect(second_room.conversation_memberships.find_by!(user: manager).reload.position).to eq(0)
    expect(first_room.conversation_memberships.find_by!(user: manager).reload.position).to eq(1)

    get "/api/v1/conversations"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("conversations").map { |conversation| conversation.fetch("id") }.first(2)).to eq(
      [ second_room.id, first_room.id ]
    )

    client = User.create!(organization:, name: "Sidebar customer", email: "sidebar-customer@example.test",
                          password: "long-enough-password", role: :client_admin)
    client_account = ClientAccount.create!(organization:, name: "Sidebar customer account", kind: :agent)
    ClientMembership.create!(client_account:, user: client, role: :admin)
    sign_out manager
    sign_in client

    post "/api/v1/conversations/reorder", params: { conversation_ids: [ first_room.id ] }

    expect(response).to have_http_status(:forbidden)
  end

  it "puts a newer customer conversation ahead of an older team conversation" do
    base_time = Time.zone.parse("2026-09-08 12:00:00")
    team_room, = create_room("Older team room")
    client_account = ClientAccount.create!(organization:, name: "Customer ordering account", kind: :agent)
    customer_room = Conversation.create!(organization:, client_account:, kind: :client, subject: "Customer room")
    customer_room.conversation_memberships.create!(user: manager, role: :manager)
    customer_room.conversation_memberships.create!(user: teammate, role: :participant)

    create_message(team_room, author: teammate, body: "Older team update", at: base_time)
    create_message(customer_room, author: teammate, body: "Newest customer update", at: base_time + 1.hour)

    get "/api/v1/conversations"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("conversations").map { |conversation| conversation.fetch("id") }.first(2)).to eq(
      [ customer_room.id, team_room.id ]
    )
  end

  it "marks a conversation read when it is opened without changing sidebar ordering" do
    room, membership = create_room("Read on open")
    message = create_message(room, author: teammate, body: "New work", at: 1.hour.ago)
    expect(membership.reload.last_read_at).to be_nil

    get "/api/v1/conversations"
    expect(response.parsed_body.fetch("conversations").find { |entry| entry["id"] == room.id }).to include(
      "unread_count" => 1
    )

    get "/api/v1/conversations/#{room.id}"

    expect(response).to have_http_status(:ok)
    expect(membership.reload.last_read_at).to be >= message.reload.created_at

    get "/api/v1/conversations"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("conversations").find { |entry| entry["id"] == room.id }).to include(
      "unread_count" => 0,
      "last_unread_message_at" => nil
    )
  end

  it "does not mark the current user's own messages as unread" do
    room, membership = create_room("Own message")
    message = create_message(room, author: manager, body: "I sent this", at: 1.hour.ago)

    get "/api/v1/conversations"

    expect(response).to have_http_status(:ok)
    entry = response.parsed_body.fetch("conversations").find { |conversation| conversation.fetch("id") == room.id }
    expect(entry).to include("unread_count" => 0, "last_unread_message_at" => nil)
    expect(membership.reload.last_read_at).to be_nil
    expect(message).to be_persisted
  end

  it "tracks customer-thread unread state for an admin who has not opened it" do
    client_account = ClientAccount.create!(organization:, name: "Unread customer account", kind: :agent)
    room = Conversation.create!(organization:, client_account:, kind: :client, subject: "Customer room")
    room.conversation_memberships.create!(user: teammate, role: :manager)
    message = create_message(room, author: teammate, body: "Customer needs an update", at: 1.hour.ago)

    sign_out manager
    sign_in admin

    get "/api/v1/conversations"

    expect(response).to have_http_status(:ok)
    entry = response.parsed_body.fetch("conversations").find { |conversation| conversation.fetch("id") == room.id }
    expect(entry).to include(
      "unread_count" => 1,
      "last_unread_message_at" => message.reload.created_at.utc.iso8601(3)
    )

    get "/api/v1/conversations/#{room.id}"

    expect(response).to have_http_status(:ok)
    expect(room.conversation_memberships.find_by!(user: admin).last_read_at).to be >= message.created_at
  end

  private

  def create_room(subject)
    room = Conversation.create!(organization:, kind: :internal, subject:)
    membership = room.conversation_memberships.create!(user: manager, role: :manager)
    room.conversation_memberships.create!(user: teammate, role: :participant)
    [ room, membership ]
  end

  def create_message(room, author:, body:, at:)
    message = room.messages.create!(author:, body:)
    message.update_columns(created_at: at, updated_at: at)
    room.update_columns(last_message_at: at, updated_at: at)
    message
  end
end
