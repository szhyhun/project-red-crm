require "rails_helper"

RSpec.describe "Browser push subscriptions", type: :request do
  let!(:organization) { Organization.create!(name: "Push agency", slug: "push-agency") }
  let!(:person) do
    User.create!(organization:, name: "Push person", email: "push-person@example.test",
                 password: "long-enough-password", role: :client_member)
  end
  let!(:other) do
    User.create!(organization:, name: "Other push person", email: "other-push@example.test",
                 password: "long-enough-password", role: :client_member)
  end

  it "does not let anyone signed out subscribe, or remove another person's browser" do
    post "/api/v1/push_subscriptions", params: { subscription: { endpoint: "https://push.example.test/1", keys: { p256dh: "k", auth: "a" } } }
    expect(response).to have_http_status(:unauthorized)

    other.push_subscriptions.create!(endpoint: "https://push.example.test/theirs", p256dh: "k", auth: "a")
    sign_in person
    delete "/api/v1/push_subscriptions", params: { endpoint: "https://push.example.test/theirs" }
    expect(other.push_subscriptions.count).to eq(1)
  end

  it "refuses an endpoint that is not https" do
    sign_in person
    post "/api/v1/push_subscriptions", params: { subscription: { endpoint: "http://push.example.test/1", keys: { p256dh: "k", auth: "a" } } }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "does not let a person take over another person's endpoint" do
    other.push_subscriptions.create!(endpoint: "https://push.example.test/shared", p256dh: "k", auth: "a")
    sign_in person

    post "/api/v1/push_subscriptions", params: {
      subscription: { endpoint: "https://push.example.test/shared", keys: { p256dh: "new-k", auth: "new-a" } }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(other.push_subscriptions.sole).to have_attributes(p256dh: "k", auth: "a")
    expect(person.push_subscriptions).to be_empty
  end

  it "subscribes and unsubscribes the person's own browser" do
    sign_in person

    get "/api/v1/push_subscriptions/settings"
    expect(response.parsed_body.fetch("push")).to include("subscribed" => false)

    post "/api/v1/push_subscriptions", params: { subscription: { endpoint: "https://push.example.test/1", keys: { p256dh: "k", auth: "a" } } }
    expect(response).to have_http_status(:created)
    expect(person.push_subscriptions.sole.endpoint).to eq("https://push.example.test/1")

    delete "/api/v1/push_subscriptions", params: { endpoint: "https://push.example.test/1" }
    expect(person.push_subscriptions).to be_empty
  end
end
