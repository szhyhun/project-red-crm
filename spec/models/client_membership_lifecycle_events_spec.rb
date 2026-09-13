require "rails_helper"

RSpec.describe ClientMembership, type: :model do
  let!(:organization) { Organization.create!(name: "Events agency", slug: "events-agency") }
  let!(:team) { ClientAccount.create!(organization:, name: "Events Team", kind: :team) }
  let!(:other_team) { ClientAccount.create!(organization:, name: "Other Events Team", kind: :team) }
  let!(:keeper) do
    User.create!(organization:, name: "Keeper", email: "events-keeper@example.test", password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account: team, user:, role: :admin, status: :active)
    end
  end
  let!(:person) { User.create!(organization:, name: "Eventful", email: "eventful@example.test", password: "long-enough-password", role: :client_member) }

  def events = ActivityEvent.where("event_type LIKE 'client_membership.%'").order(:id).pluck(:event_type)

  it "records Aryeo's lifecycle events whichever path changes a membership" do
    membership = described_class.create!(client_account: team, user: person, role: :member, status: :invited)
    membership.accept!
    membership.update!(role: :admin)
    elsewhere = described_class.create!(client_account: other_team, user: person, role: :member, status: :active)
    elsewhere.make_default!
    elsewhere.revoke!
    elsewhere.reactivate!
    membership.archive!
    membership.destroy!

    # Revoking or archiving hands the landing team on, before the status event
    # itself; a membership never accepted comes back as an invitation, so it
    # is not handed anything.
    expect(events).to eq(%w[
      client_membership.accepted client_membership.default_added client_membership.role_changed
      client_membership.default_removed client_membership.default_added
      client_membership.default_removed client_membership.default_added client_membership.revoked
      client_membership.reactivated
      client_membership.default_removed client_membership.archived
      client_membership.deleted
    ])
    expect(elsewhere.reload).to be_invited
  end
end
