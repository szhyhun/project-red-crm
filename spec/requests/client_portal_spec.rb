require "rails_helper"

RSpec.describe "Client portal", type: :request do
  it "returns only the signed-in client's listing delivery data" do
    organization = Organization.create!(name: "ProjectRed", slug: "projectred")
    own_account = ClientAccount.create!(organization: organization, name: "Avery Agent", kind: :agent)
    other_account = ClientAccount.create!(organization: organization, name: "Other Agent", kind: :agent)
    client_user = User.create!(organization: organization, name: "Avery Client", email: "avery-client@example.test", password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: own_account, user: client_user, role: :admin)
    own_listing = Listing.create!(organization: organization, client_account: own_account, address_line_1: "111 Oak Bay Avenue")
    Listing.create!(organization: organization, client_account: other_account, address_line_1: "100 Hidden Street")
    own_listing.workflow_tasks.create!(organization: organization, title: "Edit photos", stage: "editing", customer_visible: true)
    own_listing.workflow_tasks.create!(organization: organization, title: "Internal QA", stage: "review", customer_visible: false)
    MediaAsset.create!(organization: organization, listing: own_listing, kind: :final, status: :ready, storage_key: "final/photo.jpg", filename: "photo.jpg", content_type: "image/jpeg")
    MediaAsset.create!(organization: organization, listing: own_listing, kind: :final, status: :ready, storage_key: "final/internal.jpg", filename: "internal.jpg", content_type: "image/jpeg", hidden: true)
    own_listing.update!(delivered_at: Time.current)
    conversation = Conversation.create!(organization: organization, listing: own_listing, client_account: own_account, kind: :client, subject: "Editing update")
    ConversationMembership.create!(conversation: conversation, user: client_user)
    manager = User.create!(organization: organization, name: "Morgan Manager", email: "manager-client-portal@example.test", password: "long-enough-password", role: :manager)
    conversation.messages.create!(author: manager, body: "Photos are ready.")
    conversation.messages.create!(author: manager, body: "Internal note", visibility: :staff_only)

    sign_in client_user
    get "/api/v1/client_portal"

    expect(response).to have_http_status(:ok)
    listing = JSON.parse(response.body).fetch("listings").sole
    expect(listing.fetch("address")).to eq("111 Oak Bay Avenue")
    expect(listing.fetch("progress").map { |task| task.fetch("title") }).to eq(["Edit photos"])
    expect(listing.fetch("media_assets").map { |asset| asset.fetch("storage_key") }).to eq(["final/photo.jpg"])
    expect(listing.fetch("customer_first_viewed_at")).to be_present
    expect(own_listing.reload.customer_first_viewed_at).to be_present
    expect(JSON.parse(response.body).dig("conversations", 0, "messages").map { |message| message.fetch("body") }).to eq(["Photos are ready."])
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
    post "/api/v1/client_portal/appointments/#{appointment.id}/reschedule", params: {
      appointment: { starts_at: requested_start, ends_at: requested_end, notes: "After lunch, please." }
    }

    expect(response).to have_http_status(:ok)
    expect(appointment.reload).to have_attributes(status: "confirmed", request_status: "requested")
    expect(appointment.appointment_events.order(:created_at).last).to have_attributes(event_type: "customer_reschedule_requested")
    expect(JSON.parse(response.body).dig("appointment", "reschedule_request", "notes")).to eq("After lunch, please.")
    expect(listing.activity_events.where(event_type: "appointment.customer_reschedule_requested")).to exist
  end
end
