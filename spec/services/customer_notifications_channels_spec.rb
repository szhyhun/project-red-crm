require "rails_helper"

RSpec.describe CustomerNotifications do
  let!(:organization) { Organization.create!(name: "Channel agency", slug: "channel-agency") }
  let!(:team) { ClientAccount.create!(organization:, name: "Channel Team", kind: :team) }
  let!(:texter) { customer("texter", phone: "(250) 555-0101") }
  let!(:browser) { customer("browser", phone: nil) }
  let!(:listing) { Listing.create!(organization:, client_account: team, address_line_1: "12 Channel Road") }
  let(:env) do
    { "TWILIO_ACCOUNT_SID" => "AC123", "TWILIO_AUTH_TOKEN" => "secret", "TWILIO_FROM_NUMBER" => "+12505550000",
      "VAPID_PUBLIC_KEY" => "public", "VAPID_PRIVATE_KEY" => "private", "VAPID_SUBJECT" => "mailto:ops@example.test" }
  end

  def customer(handle, phone:)
    User.create!(organization:, name: handle.humanize, email: "#{handle}@example.test", phone:,
                 password: "long-enough-password", role: :client_member).tap do |user|
      ClientMembership.create!(client_account: team, user:, role: :member, status: :active)
    end
  end

  def with_channels(&)
    originals = env.keys.index_with { |key| ENV[key] }
    env.each { |key, value| ENV[key] = value }
    yield
  ensure
    originals.each { |key, value| ENV[key] = value }
  end

  it "schedules nothing on SMS or push when those channels are not configured" do
    described_class.listing_ready(listing)

    expect(NotificationDelivery.distinct.pluck(:channel)).to eq([ "email" ])
  end

  it "texts people with a phone and pushes to people with a browser, where the team allows it" do
    browser.push_subscriptions.create!(endpoint: "https://push.example.test/abc", p256dh: "key", auth: "auth")
    team.update!(notification_preferences: { "listing_delivered" => { "push" => false } })

    with_channels { described_class.listing_ready(listing) }

    expect(NotificationDelivery.by_sms.pluck(:recipient)).to eq([ "+12505550101" ])
    expect(NotificationDelivery.by_push).to be_empty
    expect(NotificationDelivery.by_email.pluck(:recipient)).to contain_exactly("texter@example.test", "browser@example.test")

    team.update!(notification_preferences: {})
    with_channels { described_class.listing_ready(listing) }
    expect(NotificationDelivery.by_push.pluck(:recipient)).to eq([ "user:#{browser.id}" ])
  end

  it "sends a text through Twilio and a push through each subscribed browser" do
    browser.push_subscriptions.create!(endpoint: "https://push.example.test/abc", p256dh: "key", auth: "auth")
    sms = instance_double(NotificationChannels::Sms, deliver: true)
    allow(NotificationChannels::Sms).to receive(:new).and_return(sms)
    allow(WebPush).to receive(:payload_send)

    with_channels do
      described_class.listing_ready(listing)
      NotificationDelivery.where.not(channel: "email").find_each { |delivery| described_class.deliver_now(delivery) }
    end

    expect(sms).to have_received(:deliver).with(to: "+12505550101", body: a_string_including("12 Channel Road is delivered"))
    expect(WebPush).to have_received(:payload_send).with(hash_including(endpoint: "https://push.example.test/abc",
                                                                        message: a_string_including("Media delivered")))
  end

  it "forgets a browser subscription the push service says has expired" do
    subscription = browser.push_subscriptions.create!(endpoint: "https://push.example.test/gone", p256dh: "key", auth: "auth")
    allow(WebPush).to receive(:payload_send).and_raise(WebPush::ExpiredSubscription.new(Struct.new(:body).new(""), "push.example.test"))

    with_channels { NotificationChannels::Push.new.deliver(user: browser, title: "t", body: "b", url: "u") }

    expect(PushSubscription.exists?(subscription.id)).to be(false)
  end
end
