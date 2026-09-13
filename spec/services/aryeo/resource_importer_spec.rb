require "rails_helper"

RSpec.describe Aryeo::ResourceImporter do
  let!(:organization) { Organization.create!(name: "Resource Import Agency", slug: "resource-import-agency") }
  let!(:connection) do
    IntegrationConnection.create!(organization:, provider: :aryeo, api_key: "aryeo-key", status: :connected)
  end
  let!(:run) do
    connection.integration_import_runs.create!(organization:, provider: :aryeo, requested_resources: %w[products clients customer_teams])
  end
  let(:session) { Aryeo::ImportSession.new(run:, client: instance_double(Aryeo::Client)) }

  it "maps an Aryeo product and its variants without creating a package" do
    product = described_class.call(
      session:,
      name: :products,
      payload: {
        "id" => "product-1",
        "type" => "MAIN",
        "title" => "Standard Property Photography",
        "categories" => [ "Photography" ],
        "variants" => [ { "id" => "variant-1", "title" => "0–1,000 sqft", "price_amount" => 29_900 } ]
      }
    )

    expect(product).to have_attributes(kind: "service", deliverable_type: "photography")
    expect(product.product_variants.sole).to have_attributes(price_cents: 29_900, sqft_min: 0, sqft_max: 1_000)
    expect(product.package_components).to be_empty
  end

  it "maps a customer team to a client account holding its people" do
    team = described_class.call(
      session:,
      name: :customer_teams,
      payload: {
        "id" => "team-1",
        "name" => "Oak Bay Realty",
        "customer_ids" => [ "customer-1" ],
        "customers" => [ { "id" => "customer-1", "name" => "Avery Agent", "email" => "avery@example.test" } ]
      }
    )

    expect(team).to be_a(ClientAccount).and have_attributes(kind: "team", origin: "aryeo")
    expect(team.client_memberships.sole).to have_attributes(status: "invited", role: "member")
    expect(team.client_memberships.sole.user).to have_attributes(email: "avery@example.test", role: "client_member")
    expect(organization.client_accounts.find_by!(email: "avery@example.test").kind).not_to eq("team")
  end

  describe "re-importing a team whose memberships changed in Aryeo" do
    def import_team(memberships)
      described_class.call(session:, name: :customer_teams, payload: {
        "id" => "team-9", "name" => "Harbour Group",
        "customer_team_memberships" => memberships.map do |email, role, status|
          { "role" => role, "status" => status, "customer_user" => { "id" => email, "email" => email, "name" => email } }
        end
      })
    end

    def membership(team, email) = team.client_memberships.joins(:user).find_by!(users: { email: })

    it "carries a new role and an ended membership, but never grants access Aryeo alone reports" do
      team = import_team([ [ "lead@example.test", "ADMIN", "ACTIVE" ], [ "helper@example.test", "MEMBER", "ACTIVE" ],
                           [ "left@example.test", "MEMBER", "ACTIVE" ] ])
      membership(team, "lead@example.test").accept!

      import_team([ [ "lead@example.test", "ADMIN", "ACTIVE" ], [ "helper@example.test", "ADMIN", "ACTIVE" ],
                    [ "left@example.test", "MEMBER", "REVOKED" ] ])

      expect(membership(team, "helper@example.test")).to have_attributes(role: "admin", status: "invited")
      expect(membership(team, "left@example.test")).to have_attributes(status: "revoked")
      expect(membership(team, "lead@example.test")).to have_attributes(role: "admin", status: "active")
    end

    it "keeps a change our own rules refuse, such as demoting the billing member" do
      team = import_team([ [ "payer@example.test", "ADMIN", "ACTIVE" ], [ "other@example.test", "ADMIN", "ACTIVE" ] ])
      payer = membership(team, "payer@example.test").tap(&:accept!)
      membership(team, "other@example.test").accept!
      team.update!(billing_user: payer.user)

      expect { import_team([ [ "payer@example.test", "MEMBER", "ACTIVE" ], [ "other@example.test", "ADMIN", "ACTIVE" ] ]) }
        .not_to raise_error
      expect(payer.reload).to be_admin
    end
  end
end
