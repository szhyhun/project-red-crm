require "rails_helper"

RSpec.describe "Conversation creation API scenario", type: :request do
  let!(:organization) { Organization.create!(name: "Conversation creation agency", slug: "conversation-creation-agency") }
  let!(:other_organization) do
    Organization.create!(name: "Other conversation creation agency", slug: "other-conversation-creation-agency")
  end
  let!(:manager) do
    User.create!(organization:, name: "Creation manager", email: "conversation-creation-manager@example.test",
                password: "long-enough-password", role: :manager)
  end
  let!(:producer) do
    User.create!(organization:, name: "Creation producer", email: "conversation-creation-producer@example.test",
                password: "long-enough-password", role: :production_staff)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Creation client", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Creation customer", email: "conversation-creation-client@example.test",
                password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:, role: :admin)
    end
  end

  before do
    allow(Conversations::NotifyJob).to receive(:perform_later)
    sign_in manager
  end

  it "creates an internal conversation with its initial message and staff members" do
    expect {
      post "/api/v1/conversations", params: {
        conversation: {
          kind: "internal",
          subject: "Production handoff",
          member_ids: [ producer.id ],
          body: "Please review the delivery queue."
        }
      }
    }.to change(Conversation, :count).by(1).and change(Message, :count).by(1)

    expect(response).to have_http_status(:created)
    conversation = Conversation.order(:id).last
    expect(conversation).to have_attributes(kind: "internal", client_account_id: nil, listing_id: nil)
    expect(conversation.users).to contain_exactly(manager, producer)
    expect(conversation.messages.sole).to have_attributes(author: manager, body: "Please review the delivery queue.")
    expect(response.parsed_body.dig("conversation", "messages").sole).to include(
      "body" => "Please review the delivery queue.", "message_kind" => "message"
    )
  end

  it "creates one account-wide customer conversation and makes it readable by the customer" do
    post "/api/v1/conversations", params: {
      conversation: {
        kind: "client",
        client_account_id: client_account.id,
        subject: "Project updates",
        body: "We will post production updates here."
      }
    }

    expect(response).to have_http_status(:created)
    conversation = Conversation.order(:id).last
    expect(conversation).to have_attributes(kind: "client", client_account:, listing_id: nil)
    expect(conversation.users).to contain_exactly(manager, client_user)

    sign_out manager
    sign_in client_user
    get "/api/v1/conversations/#{conversation.id}"

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("conversation", "messages").sole).to include(
      "body" => "We will post production updates here.", "author" => hash_including("id" => manager.id)
    )
  end

  it "creates one empty account-wide conversation per selected customer account" do
    second_account = ClientAccount.create!(organization:, name: "Second creation client", kind: :team)
    second_client = User.create!(organization:, name: "Second creation customer", email: "conversation-creation-client-2@example.test",
                                 password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: second_account, user: second_client, role: :admin)

    expect {
      post "/api/v1/conversations", params: {
        conversation: {
          kind: "client",
          subject: "Customer rollout",
          client_account_ids: [ client_account.id, second_account.id ],
          member_ids: [ producer.id ]
        }
      }
    }.to change(Conversation, :count).by(2)

    expect(response).to have_http_status(:created)
    created = response.parsed_body.fetch("conversations")
    expect(created.map { |conversation| conversation.fetch("client_account_id") }).to contain_exactly(client_account.id, second_account.id)
    expect(created).to all(include("listing_id" => nil, "messages" => []))
    expect(Conversation.where(client_account_id: [ client_account.id, second_account.id ]).map(&:users)).to all(
      satisfy { |users| users.include?(manager) && users.include?(producer) }
    )
    expect(Conversation.find_by!(client_account: client_account).users).to include(client_user)
    expect(Conversation.find_by!(client_account: second_account).users).to include(second_client)
  end

  it "rejects selected customer accounts outside the current organization" do
    foreign_account = ClientAccount.create!(organization: other_organization, name: "Foreign creation client", kind: :agent)

    expect {
      post "/api/v1/conversations", params: {
        conversation: {
          kind: "client",
          subject: "Cross tenant customer room",
          client_account_ids: [ foreign_account.id ]
        }
      }
    }.not_to change(Conversation, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "client_account_ids")).to include("contains an unavailable customer account")
  end

  it "leaves no customer room behind when a selected member is unavailable" do
    expect {
      post "/api/v1/conversations", params: {
        conversation: {
          kind: "client",
          subject: "Room with a missing member",
          client_account_ids: [ client_account.id ],
          member_ids: [ 999_999 ]
        }
      }
    }.not_to change(Conversation, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("details", "member_ids")).to include("contains an unavailable organization member")
  end

  it "does not allow a customer to create an internal conversation with a client member" do
    sign_out manager
    sign_in client_user

    expect {
      post "/api/v1/conversations", params: {
        conversation: {
          kind: "internal",
          subject: "Unauthorized internal room",
          member_ids: [ manager.id ]
        }
      }
    }.not_to change(Conversation, :count)

    expect(response).to have_http_status(:forbidden)
    expect(Conversation.find_by(subject: "Unauthorized internal room")).to be_nil
  end

  it "rejects a requested member from another organization without creating the room" do
    foreign_user = User.create!(organization: other_organization, name: "Foreign member",
                                email: "conversation-creation-foreign@example.test",
                                password: "long-enough-password", role: :production_staff)

    expect {
      post "/api/v1/conversations", params: {
        conversation: {
          kind: "internal",
          subject: "Cross tenant room",
          member_ids: [ foreign_user.id ]
        }
      }
    }.not_to change(Conversation, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(Conversation.find_by(subject: "Cross tenant room")).to be_nil
  end
end
