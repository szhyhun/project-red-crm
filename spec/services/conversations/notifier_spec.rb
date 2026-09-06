require "rails_helper"

RSpec.describe Conversations::Notifier do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-notifier") }
  let!(:author) { staff("notifier-author@example.test", :manager) }
  let!(:teammate) { staff("notifier-teammate@example.test", :production_staff) }
  let!(:client_account) { ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent) }
  let!(:customer) do
    User.create!(organization:, name: "Avery", email: "notifier-client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:)
    end
  end
  let!(:conversation) do
    Conversation.create!(organization:, kind: :client, client_account:, subject: "Delivery").tap do |record|
      [ author, teammate, customer ].each { |user| record.conversation_memberships.create!(user:) }
    end
  end

  def staff(email, role)
    User.create!(organization:, name: email.split("@").first, email:, password: "long-enough-password", role:)
  end

  def stream_for(user)
    NotificationChannel.broadcasting_for(user)
  end

  it "tells every participant except the author" do
    message = conversation.messages.create!(author:, body: "Files are up")

    expect { described_class.call(message:) }
      .to have_broadcasted_to(stream_for(teammate)).exactly(:once)
      .and have_broadcasted_to(stream_for(customer)).exactly(:once)
  end

  it "never tells the author about their own message" do
    message = conversation.messages.create!(author:, body: "Files are up")

    expect { described_class.call(message:) }.not_to have_broadcasted_to(stream_for(author))
  end

  # Visibility is decided at broadcast time so the channel carries no rules.
  it "withholds a staff-only message from a client participant" do
    message = conversation.messages.create!(author:, body: "Internal note", visibility: :staff_only)

    expect { described_class.call(message:) }.to have_broadcasted_to(stream_for(teammate)).exactly(:once)
    expect { described_class.call(message:) }.not_to have_broadcasted_to(stream_for(customer))
  end
end
