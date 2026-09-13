require "rails_helper"

RSpec.describe ClientAccount, type: :model do
  let!(:organization) { Organization.create!(name: "Code agency", slug: "code-agency") }

  it "holds one affiliate code per organization whatever its case, even past the model" do
    described_class.create!(organization:, name: "Coast", affiliate_id: "COAST")
    twin = described_class.new(organization:, name: "Coast twin", affiliate_id: "coast")

    expect(twin).not_to be_valid
    expect { twin.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "lets another organization use the same code" do
    described_class.create!(organization:, name: "Coast", affiliate_id: "COAST")
    other = Organization.create!(name: "Other code agency", slug: "other-code-agency")

    expect(described_class.create!(organization: other, name: "Their coast", affiliate_id: "coast")).to be_persisted
  end
end
