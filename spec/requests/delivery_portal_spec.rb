require "rails_helper"

RSpec.describe "Delivery portal", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred") }
  let!(:client_account) { ClientAccount.create!(organization: organization, name: "Avery Agent", kind: :agent) }
  let!(:listing) { Listing.create!(organization: organization, client_account: client_account, address_line_1: "111 Oak Bay Avenue") }

  it "publishes only ready final media on a property site" do
    site = PropertySite.create!(organization: organization, listing: listing, slug: "111-oak-bay", status: :published, published_at: Time.current)
    MediaAsset.create!(organization: organization, listing: listing, kind: :final, status: :ready, storage_key: "final/photo.jpg", filename: "photo.jpg", content_type: "image/jpeg")
    MediaAsset.create!(organization: organization, listing: listing, kind: :final, status: :processing, storage_key: "final/video.mp4", filename: "video.mp4", content_type: "video/mp4")
    MediaAsset.create!(organization: organization, listing: listing, kind: :raw, status: :ready, storage_key: "raw/source.mov", filename: "source.mov", content_type: "video/quicktime")

    get "/api/v1/public/property_sites/#{organization.slug}/#{site.slug}"

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("property_site", "media_assets").map { |asset| asset.fetch("storage_key") }).to eq(["final/photo.jpg"])
  end

  it "does not expose staff-only messages to a client participant" do
    client_user = User.create!(organization: organization, name: "Avery Client", email: "avery-client@example.test", password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: client_account, user: client_user, role: :admin)
    staff_user = User.create!(organization: organization, name: "Morgan Manager", email: "morgan-manager@example.test", password: "long-enough-password", role: :manager)
    conversation = Conversation.create!(organization: organization, listing: listing, client_account: client_account, kind: :client, subject: "Delivery")
    ConversationMembership.create!(conversation: conversation, user: client_user)
    ConversationMembership.create!(conversation: conversation, user: staff_user, role: :manager)
    conversation.messages.create!(author: staff_user, body: "Client-visible update")
    conversation.messages.create!(author: staff_user, body: "Internal note", visibility: :staff_only)

    sign_in client_user
    get "/api/v1/conversations/#{conversation.id}"

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig("conversation", "messages").map { |message| message.fetch("body") }).to eq(["Client-visible update"])
  end

  it "adds every client account user to a new client conversation" do
    manager = User.create!(organization: organization, name: "Morgan Manager", email: "manager-conversation@example.test", password: "long-enough-password", role: :manager)
    client_user = User.create!(organization: organization, name: "Avery Client", email: "client-conversation@example.test", password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: client_account, user: client_user, role: :admin)

    sign_in manager
    post "/api/v1/conversations", params: { conversation: { listing_id: listing.id, kind: "client", subject: "Shoot update", body: "We are booked." } }

    expect(response).to have_http_status(:created)
    conversation = Conversation.order(:id).last
    expect(conversation.conversation_memberships.where(user: client_user)).to exist
  end

  it "creates a customer conversation without requiring a listing" do
    manager = User.create!(organization: organization, name: "Morgan Manager", email: "customer-room-manager@example.test", password: "long-enough-password", role: :manager)
    client_user = User.create!(organization: organization, name: "Avery Client", email: "customer-room-client@example.test", password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: client_account, user: client_user, role: :admin)

    sign_in manager
    post "/api/v1/conversations", params: { conversation: { client_account_id: client_account.id, kind: "client", subject: "Account updates", body: "Welcome." } }

    expect(response).to have_http_status(:created)
    conversation = Conversation.order(:id).last
    expect(conversation).to have_attributes(client_account: client_account, listing: nil)
    expect(conversation.users).to contain_exactly(manager, client_user)
  end

  it "rejects a customer room when its listing belongs to another customer" do
    manager = User.create!(organization: organization, name: "Morgan Manager", email: "mismatched-room-manager@example.test", password: "long-enough-password", role: :manager)
    other_account = ClientAccount.create!(organization: organization, name: "Other Client", kind: :agent)

    sign_in manager
    post "/api/v1/conversations", params: { conversation: { listing_id: listing.id, client_account_id: other_account.id, kind: "client", subject: "Wrong account", body: "Hello." } }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body).dig("details", "listing")).to include("must belong to the selected customer account")
  end

  it "allows a client participant to reply to a client conversation" do
    client_user = User.create!(organization: organization, name: "Avery Client", email: "reply-client@example.test", password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: client_account, user: client_user, role: :admin)
    manager = User.create!(organization: organization, name: "Morgan Manager", email: "reply-manager@example.test", password: "long-enough-password", role: :manager)
    conversation = Conversation.create!(organization: organization, listing: listing, client_account: client_account, kind: :client, subject: "Delivery")
    ConversationMembership.create!(conversation: conversation, user: client_user)
    ConversationMembership.create!(conversation: conversation, user: manager, role: :manager)

    sign_in client_user
    post "/api/v1/conversations/#{conversation.id}/messages", params: { message: { body: "Thank you." } }

    expect(response).to have_http_status(:created)
    expect(conversation.messages.last).to have_attributes(author: client_user, body: "Thank you.", visibility: "participants")
  end

  it "creates an organization-level conversation for selected staff" do
    admin = User.create!(organization: organization, name: "Alex Admin", email: "chat-admin@example.test", password: "long-enough-password", role: :organization_admin)
    producer = User.create!(organization: organization, name: "Parker Producer", email: "chat-producer@example.test", password: "long-enough-password", role: :production_staff)

    sign_in admin
    post "/api/v1/conversations", params: { conversation: { kind: "internal", subject: "Studio updates", body: "Welcome to the team chat.", member_ids: [producer.id] } }

    expect(response).to have_http_status(:created)
    conversation = Conversation.order(:id).last
    expect(conversation).to have_attributes(kind: "internal", listing_id: nil, client_account_id: nil)
    expect(conversation.users).to contain_exactly(admin, producer)
  end

  it "limits internal staff to conversations where they are members" do
    admin = User.create!(organization: organization, name: "Alex Admin", email: "scope-admin@example.test", password: "long-enough-password", role: :organization_admin)
    member = User.create!(organization: organization, name: "Morgan Member", email: "scope-member@example.test", password: "long-enough-password", role: :manager)
    outsider = User.create!(organization: organization, name: "Parker Outsider", email: "scope-outsider@example.test", password: "long-enough-password", role: :production_staff)
    conversation = Conversation.create!(organization: organization, kind: :internal, subject: "Private production")
    conversation.conversation_memberships.create!(user: admin, role: :manager)
    conversation.conversation_memberships.create!(user: member)

    sign_in outsider
    get "/api/v1/conversations"

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).fetch("conversations")).to be_empty
  end


  it "allows a room manager to invite and remove an organization participant" do
    manager = User.create!(organization: organization, name: "Morgan Manager", email: "room-manager@example.test", password: "long-enough-password", role: :manager)
    producer = User.create!(organization: organization, name: "Parker Producer", email: "room-producer@example.test", password: "long-enough-password", role: :production_staff)
    conversation = Conversation.create!(organization: organization, kind: :internal, subject: "Production room")
    conversation.conversation_memberships.create!(user: manager, role: :manager)

    sign_in manager
    post "/api/v1/conversations/#{conversation.id}/members", params: { conversation_membership: { user_id: producer.id } }

    expect(response).to have_http_status(:created)
    membership = conversation.conversation_memberships.find_by!(user: producer)

    sign_in manager
    delete "/api/v1/conversations/#{conversation.id}/members/#{membership.id}"

    expect(response).to have_http_status(:no_content)
    expect(conversation.conversation_memberships.where(user: producer)).not_to exist
  end

  it "does not let an ordinary room participant manage members" do
    manager = User.create!(organization: organization, name: "Morgan Manager", email: "locked-room-manager@example.test", password: "long-enough-password", role: :manager)
    participant = User.create!(organization: organization, name: "Parker Participant", email: "locked-room-participant@example.test", password: "long-enough-password", role: :production_staff)
    invitee = User.create!(organization: organization, name: "Taylor Invitee", email: "locked-room-invitee@example.test", password: "long-enough-password", role: :production_staff)
    conversation = Conversation.create!(organization: organization, kind: :internal, subject: "Private room")
    conversation.conversation_memberships.create!(user: manager, role: :manager)
    conversation.conversation_memberships.create!(user: participant)

    sign_in participant
    post "/api/v1/conversations/#{conversation.id}/members", params: { conversation_membership: { user_id: invitee.id } }

    expect(response).to have_http_status(:forbidden)
    expect(conversation.conversation_memberships.where(user: invitee)).not_to exist
  end
end
