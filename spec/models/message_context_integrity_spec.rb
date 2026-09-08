require "rails_helper"

RSpec.describe Message, type: :model do
  let!(:organization) { Organization.create!(name: "Message context agency", slug: "message-context-agency") }
  let!(:other_organization) { Organization.create!(name: "Other message context agency", slug: "other-message-context") }
  let!(:author) do
    User.create!(organization:, name: "Context author", email: "message-context-author@example.test",
                 password: "long-enough-password", role: :manager)
  end
  let!(:client_account) { ClientAccount.create!(organization:, name: "Context client", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account:, address_line_1: "72 Message Context Street") }
  let!(:conversation) { Conversation.create!(organization:, kind: :internal, subject: "Context room") }
  let!(:other_client_account) { ClientAccount.create!(organization: other_organization, name: "Other client", kind: :agent) }
  let!(:other_listing) { Listing.create!(organization: other_organization, client_account: other_client_account, address_line_1: "Other street") }

  it "sanitizes HTML and derives the searchable plain-text body before persistence" do
    message = conversation.messages.build(
      author:, body: "stale body", body_html: '<p><strong>Ready</strong></p><a href="javascript:bad">unsafe</a>'
    )

    expect(message).to be_valid
    expect { message.save! }.to change(Message, :count).by(1)
    expect(message.reload).to have_attributes(body: "Ready\nunsafe")
    expect(message.body_html).to include("<strong>Ready</strong>")
    expect(message.body_html).not_to include("javascript:")
  end

  it "keeps a listing context inside the conversation organization and account" do
    message = conversation.messages.build(author:, body: "Context", listing: listing)

    expect(message).to be_valid

    message.listing = other_listing

    expect(message).not_to be_valid
    expect(message.errors.full_messages).to include("Listing must belong to the conversation organization")
  end

  it "does not allow a customer conversation context to point at another account" do
    customer_conversation = Conversation.create!(organization:, kind: :client, client_account:)
    message = customer_conversation.messages.build(author:, body: "Wrong listing", listing: other_listing)

    expect(message).not_to be_valid
    expect(message.errors.full_messages).to include("Listing must belong to the conversation organization")
  end
end
