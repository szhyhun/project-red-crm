require "rails_helper"

RSpec.describe "Client portal", type: :request do
  it "keeps internal users out of the property-first portal" do
    organization = Organization.create!(name: "ProjectRed", slug: "portal-internal")
    manager = User.create!(organization:, name: "Manager", email: "portal-internal@example.test",
                           password: "long-enough-password", role: :manager)

    sign_in manager
    get "/api/v1/portal/dashboard"

    expect(response).to have_http_status(:forbidden)
  end

  it "returns only the signed-in client's listing delivery data" do
    organization = Organization.create!(name: "ProjectRed", slug: "projectred")
    own_account = ClientAccount.create!(organization: organization, name: "Avery Agent", kind: :agent)
    other_account = ClientAccount.create!(organization: organization, name: "Other Agent", kind: :agent)
    client_user = User.create!(organization: organization, name: "Avery Client", email: "avery-client@example.test", password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: own_account, user: client_user, role: :admin)
    own_listing = Listing.create!(organization: organization, client_account: own_account, address_line_1: "111 Oak Bay Avenue",
                                  status: :in_production, property_status: :for_sale, property_type: "Detached",
                                  price_cents: 850_000, lot_acres: 0.25, parking: "Double garage", year_built: 1998,
                                  mls_number: "MLS-111", mls_live_date: Date.new(2026, 7, 3))
    Listing.create!(organization: organization, client_account: other_account, address_line_1: "100 Hidden Street")
    own_listing.workflow_tasks.create!(organization: organization, board: organization.default_board, title: "Edit photos", customer_visible: true)
    own_listing.workflow_tasks.create!(organization: organization, board: organization.default_board, title: "Internal QA", customer_visible: false)
    internal_board = organization.boards.create!(name: "CRM Development", kind: "internal", visibility: "organization",
                                                 requires_listing: true, client_visible: false, position: 1)
    WorkflowColumn::DEFAULTS.each { |attributes| internal_board.workflow_columns.create!(attributes.merge(organization: organization)) }
    own_listing.workflow_tasks.build(organization: organization, board: internal_board, title: "Internal Board Task",
                                     customer_visible: true).save!(validate: false)
    MediaAsset.create!(organization: organization, listing: own_listing, kind: :final, status: :ready, storage_key: "final/photo.jpg", filename: "photo.jpg", content_type: "image/jpeg")
    MediaAsset.create!(organization: organization, listing: own_listing, kind: :final, status: :ready, storage_key: "final/internal.jpg", filename: "internal.jpg", content_type: "image/jpeg", hidden: true)
    allow(DeliveryStorage).to receive(:public_url).with("final/photo.jpg").and_return("https://cdn.example.test/final/photo.jpg")
    own_listing.update!(delivered_at: Time.current)
    conversation = Conversation.create!(organization: organization, listing: own_listing, client_account: own_account, kind: :client, subject: "Editing update")
    ConversationMembership.create!(conversation: conversation, user: client_user)
    manager = User.create!(organization: organization, name: "Morgan Manager", email: "manager-client-portal@example.test", password: "long-enough-password", role: :manager)
    conversation.messages.create!(author: manager, body: "Photos are ready.")
    conversation.messages.create!(author: manager, body: "Internal note", visibility: :staff_only)

    sign_in client_user
    get "/api/v1/portal/dashboard"

    expect(response).to have_http_status(:ok)
    listing = JSON.parse(response.body).fetch("listings").sole
    expect(listing.fetch("address")).to eq("111 Oak Bay Avenue")
    expect(listing).to include(
      "property_status" => "for_sale",
      "property_status_label" => "For Sale",
      "property_type" => "Detached",
      "price_cents" => 850_000,
      "lot_acres" => "0.25",
      "parking" => "Double garage",
      "year_built" => 1998,
      "mls_number" => "MLS-111",
      "mls_live_date" => "2026-07-03",
      "lifecycle_status" => "delivered",
      "lifecycle_label" => "Delivered"
    )
    expect(listing.fetch("status")).not_to eq("in_production")
    expect(listing.fetch("progress").map { |task| task.fetch("title") }).to eq([ "Edit photos" ])
    expect(listing.fetch("media_assets").map { |asset| asset.fetch("filename") }).to eq([ "photo.jpg" ])
    expect(listing.fetch("media_assets").first).not_to have_key("storage_key")
    expect(listing.fetch("media_assets").first).not_to have_key("metadata")
    expect(listing.dig("media_assets", 0, "cdn_url")).to eq("https://cdn.example.test/final/photo.jpg")
    expect(listing.fetch("customer_first_viewed_at")).to be_present
    expect(own_listing.reload.customer_first_viewed_at).to be_present
    expect(JSON.parse(response.body).dig("conversations", 0, "messages").map { |message| message.fetch("body") }).to eq([ "Photos are ready." ])
  end

  it "records a customer reschedule request without changing the confirmed appointment" do
    organization = Organization.create!(name: "Reschedule Agency", slug: "reschedule-agency")
    client = ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent)
    client_user = User.create!(organization:, name: "Avery Client", email: "reschedule-client@example.test", password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: client, user: client_user, role: :admin)
    listing = Listing.create!(organization:, client_account: client, address_line_1: "27 Delivery Street")
    appointment = Appointment.create!(organization:, listing:, starts_at: 2.days.from_now, ends_at: 2.days.from_now + 1.hour, status: :confirmed)
    requested_start = 3.days.from_now.change(sec: 0).iso8601
    requested_end = (3.days.from_now + 1.hour).change(sec: 0).iso8601

    sign_in client_user
    post "/api/v1/portal/appointments/#{appointment.id}/reschedule", params: {
      appointment: { starts_at: requested_start, ends_at: requested_end, notes: "After lunch, please." }
    }

    expect(response).to have_http_status(:ok)
    expect(appointment.reload).to have_attributes(status: "confirmed", request_status: "requested")
    expect(appointment.appointment_events.order(:created_at).last).to have_attributes(event_type: "customer_reschedule_requested")
    expect(JSON.parse(response.body).dig("appointment", "reschedule_request", "notes")).to eq("After lunch, please.")
    expect(listing.activity_events.where(event_type: "appointment.customer_reschedule_requested")).to exist
  end

  it "scopes listing detail to the signed-in client's accounts" do
    organization = Organization.create!(name: "Portal Scope", slug: "portal-scope")
    own_account = ClientAccount.create!(organization:, name: "Own Account", kind: :agent)
    other_account = ClientAccount.create!(organization:, name: "Other Account", kind: :agent)
    client_user = User.create!(organization:, name: "Portal Client", email: "portal-scope@example.test",
                               password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: own_account, user: client_user, role: :admin)
    own_listing = Listing.create!(organization:, client_account: own_account, address_line_1: "Own Street")
    other_listing = Listing.create!(organization:, client_account: other_account, address_line_1: "Hidden Street")

    sign_in client_user
    get "/api/v1/portal/listings/#{other_listing.id}"
    expect(response).to have_http_status(:not_found)

    get "/api/v1/portal/listings/#{own_listing.id}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("listing", "address")).to eq("Own Street")
  end

  it "lets a client request a property-first listing for their account" do
    organization = Organization.create!(name: "Portal Create", slug: "portal-create")
    account = ClientAccount.create!(organization:, name: "Create Account", kind: :agent)
    client_user = User.create!(organization:, name: "Portal Client", email: "portal-create@example.test",
                               password: "long-enough-password", role: :client_member)
    ClientMembership.create!(client_account: account, user: client_user, role: :member)

    sign_in client_user
    post "/api/v1/portal/listings", params: {
      listing: {
        address_line_1: "27 Request Street", city: "Victoria", province: "BC",
        property_status: "for_sale", property_type: "Townhome", bedrooms: 3,
        bathrooms: 2.5, price_cents: 725_000
      }
    }

    expect(response).to have_http_status(:created)
    listing = Listing.order(:id).last
    expect(listing).to have_attributes(
      client_account_id: account.id,
      status: "draft",
      property_status: "for_sale",
      property_type: "Townhome",
      price_cents: 725_000
    )
    expect(response.parsed_body.dig("listing", "lifecycle_status")).to eq("request_received")
  end
end
