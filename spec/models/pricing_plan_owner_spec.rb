require "rails_helper"

RSpec.describe PricingPlan, type: :model do
  let!(:organization) { Organization.create!(name: "Owner agency", slug: "owner-agency") }
  let!(:account) { ClientAccount.create!(organization:, name: "Owner team", kind: :team) }
  let!(:person) do
    User.create!(organization:, name: "Owner person", email: "owner-person@example.test",
                 password: "long-enough-password", role: :client_member)
  end

  it "stores a plan promised to one person" do
    plan = organization.pricing_plans.create!(name: "Promised rate", user: person)

    expect(plan.reload.user).to eq(person)
  end

  it "refuses a plan with two owners, in the model and in the database" do
    plan = organization.pricing_plans.build(name: "Confused", client_account: account, user: person)

    expect(plan).not_to be_valid
    expect(plan.errors.full_messages).to include("must belong to exactly one team or person")
    expect { plan.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid, /pricing_plans_exactly_one_owner/)
  end

  it "refuses a plan with no owner" do
    plan = organization.pricing_plans.build(name: "Orphan")

    expect(plan).not_to be_valid
  end
end
