require "rails_helper"

RSpec.describe "Listing workspace", type: :request do
  let(:organization) { Organization.create!(name: "Workspace Agency", slug: "workspace-agency") }
  let(:manager) { User.create!(organization:, name: "Manager", email: "workspace@example.test", password: "long-enough-password", role: :manager) }
  let(:producer) { User.create!(organization:, name: "Producer", email: "producer@example.test", password: "long-enough-password", role: :production_staff) }
  let(:client) { ClientAccount.create!(organization:, name: "Agent", email: "agent@example.test", kind: :agent) }
  let(:listing) { Listing.create!(organization:, client_account: client, address_line_1: "111 Oak Bay Avenue") }

  before { sign_in manager }

  it "returns notes, payroll, feedback, appointments, and activity in listing details" do
    ListingNote.create!(organization:, listing:, author: manager, note_type: :listing, body: "Gate code is 1234")
    PayrollItem.create!(organization:, listing:, team_member: producer, created_by: manager, title: "Photo edit", amount_cents: 12_500)
    ListingFeedback.create!(organization:, listing:, client_account: client, delivery_rating: 4, service_rating: 3, media_rating: 4, submitted_at: Time.current)
    Appointment.create!(organization:, listing:, assigned_user: producer, starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)

    get "/api/v1/listings/#{listing.id}"

    expect(response).to have_http_status(:ok)
    workspace = response.parsed_body.fetch("listing")
    expect(workspace.fetch("listing_notes").first.fetch("body")).to eq("Gate code is 1234")
    expect(workspace.fetch("payroll_items").first.fetch("amount_cents")).to eq(12_500)
    expect(workspace.fetch("listing_feedbacks").first.fetch("media_rating")).to eq(4)
    expect(workspace.fetch("appointments").first.dig("assigned_user", "name")).to eq("Producer")
  end

  it "sanitizes rich listing notes before returning them" do
    post "/api/v1/listings/#{listing.id}/listing_notes", params: {
      listing_note: { note_type: "listing", body_html: '<p><strong>Gate code</strong></p><script>alert("x")</script><a href="https://example.test">Map</a>' }
    }

    expect(response).to have_http_status(:created)
    note = response.parsed_body.fetch("listing_note")
    expect(note.fetch("body_format")).to eq("html")
    expect(note.fetch("body_html")).to include("<strong>Gate code</strong>")
    expect(note.fetch("body_html")).to include('href="https://example.test"')
    expect(note.fetch("body_html")).not_to include("script")
  end

  it "marks low feedback as needing attention" do
    post "/api/v1/listings/#{listing.id}/listing_feedbacks", params: { listing_feedback: {} }
    expect(response).to have_http_status(:created)
    feedback_id = response.parsed_body.dig("listing_feedback", "id")
    sign_in manager

    patch "/api/v1/listing_feedbacks/#{feedback_id}", params: {
      listing_feedback: { delivery_rating: 2, service_rating: 4, media_rating: 4, comment: "Delivery was late" }
    }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("listing_feedback")).to include(
      "follow_up_status" => "needed", "comment" => "Delivery was late"
    )
  end

  it "lets an attached customer submit only their own requested feedback" do
    second_customer = organization.client_accounts.create!(name: "Second Customer", email: "second@example.test", kind: :agent)
    listing.listing_customers.create!(client_account: second_customer)
    feedback = ListingFeedback.create!(organization:, listing:, client_account: second_customer, requested_at: Time.current)
    client_user = User.create!(organization:, name: "Second Client", email: "feedback-client@example.test", password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: second_customer, user: client_user, role: :admin)

    sign_out manager
    sign_in client_user
    patch "/api/v1/listing_feedbacks/#{feedback.id}", params: {
      listing_feedback: { delivery_rating: 4, service_rating: 4, media_rating: 3, comment: "Looks great." }
    }

    expect(response).to have_http_status(:ok)
    expect(feedback.reload).to have_attributes(submitted_at: be_present, comment: "Looks great.", follow_up_status: "no_follow_up")
  end

  it "creates feedback requests for every customer when delivery is completed" do
    second_customer = organization.client_accounts.create!(name: "Second Customer", email: "second-delivery@example.test", kind: :agent)
    listing.listing_customers.create!(client_account: second_customer)

    expect {
      patch "/api/v1/listings/#{listing.id}", params: { listing: { delivery_status: "delivered", status: "delivered" } }
    }.to change(ListingFeedback, :count).by(2)

    expect(response).to have_http_status(:ok)
    expect(listing.reload.delivered_at).to be_present
    expect(listing.listing_feedbacks.pluck(:client_account_id)).to contain_exactly(client.id, second_customer.id)
    expect(NotificationDelivery.where(kind: "feedback_requested").count).to eq(2)
  end

  it "keeps hidden delivery media out of the client scope" do
    visible = MediaAsset.create!(organization:, listing:, uploaded_by: manager, kind: :final, status: :ready,
                                 storage_key: "visible.jpg", filename: "visible.jpg", content_type: "image/jpeg", customer_visible: true)
    MediaAsset.create!(organization:, listing:, uploaded_by: manager, kind: :final, status: :ready,
                       storage_key: "internal.jpg", filename: "internal.jpg", content_type: "image/jpeg", customer_visible: false)
    client_user = User.create!(organization:, name: "Customer", email: "customer-workspace@example.test", password: "long-enough-password", role: :client_admin)
    ClientMembership.create!(client_account: client, user: client_user, role: :admin)
    sign_out manager
    sign_in client_user

    get "/api/v1/media_assets", params: { listing_id: listing.id }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("media_assets").pluck("id")).to eq([ visible.id ])
  end


  it "adds a second customer and custom field to a listing" do
    second_customer = organization.client_accounts.create!(name: "Second Customer", email: "second@example.com")

    post "/api/v1/listings/#{listing.id}/listing_customers", params: {
      listing_customer: { client_account_id: second_customer.id }
    }
    expect(response).to have_http_status(:created)

    sign_in manager
    post "/api/v1/listings/#{listing.id}/listing_custom_fields", params: {
      listing_custom_field: { name: "Lockbox", value: "1234" }
    }
    expect(response).to have_http_status(:created)

    sign_in manager
    get "/api/v1/listings/#{listing.id}"
    workspace = response.parsed_body.fetch("listing")
    expect(workspace.fetch("listing_customers").map { |customer| customer.dig("client_account", "name") }).to include("Second Customer")
    expect(workspace.fetch("listing_custom_fields")).to include(hash_including("name" => "Lockbox", "value" => "1234"))
  end

  it "allows an internal user to update an attached customer's contact details" do
    patch "/api/v1/client_accounts/#{client.id}", params: {
      client_account: { name: "Updated Agent", email: "updated@example.com", phone: "250-555-0100", brokerage_name: "Updated Realty" }
    }

    expect(response).to have_http_status(:ok)
    expect(client.reload).to have_attributes(name: "Updated Agent", email: "updated@example.com", phone: "250-555-0100", brokerage_name: "Updated Realty")
  end

  it "soft cancels appointments and preserves their history" do
    appointment = organization.appointments.create!(listing:, starts_at: 1.day.from_now, ends_at: 1.day.from_now + 1.hour)

    delete "/api/v1/appointments/#{appointment.id}"

    expect(response).to have_http_status(:ok)
    expect(appointment.reload).to be_cancelled
    expect(appointment.appointment_events.last.event_type).to eq("cancelled")
  end
end
