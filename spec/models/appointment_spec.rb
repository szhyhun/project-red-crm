require "rails_helper"

RSpec.describe Appointment do
  it "prevents overlapping work for the same staff member" do
    organization = Organization.create!(name: "ProjectRed", slug: "projectred")
    staff = User.create!(organization:, name: "Taylor", email: "taylor@example.test", password: "long-enough-password", role: :production_staff)
    client = ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent)
    listing = Listing.create!(organization:, client_account: client, address_line_1: "111 Oak Bay Avenue")
    starts_at = Time.zone.parse("2026-08-15 10:00")
    described_class.create!(organization:, listing:, assigned_user: staff, starts_at:, ends_at: starts_at + 2.hours)

    conflict = described_class.new(organization:, listing:, assigned_user: staff, starts_at: starts_at + 1.hour, ends_at: starts_at + 3.hours)

    expect(conflict).not_to be_valid
    expect(conflict.errors[:assigned_user]).to include("already has an appointment during this time")
  end

  it "enforces staff availability at the database boundary" do
    organization = Organization.create!(name: "ProjectRed DB", slug: "projectred-db")
    staff = User.create!(organization:, name: "Taylor", email: "taylor-db@example.test", password: "long-enough-password", role: :production_staff)
    client = ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent)
    listing = Listing.create!(organization:, client_account: client, address_line_1: "112 Oak Bay Avenue")
    starts_at = Time.zone.parse("2026-08-15 10:00")
    described_class.create!(organization:, listing:, assigned_user: staff, starts_at:, ends_at: starts_at + 2.hours)

    expect do
      described_class.insert_all!([{
        organization_id: organization.id, listing_id: listing.id, assigned_user_id: staff.id,
        status: "scheduled", starts_at: starts_at + 1.hour, ends_at: starts_at + 3.hours,
        created_at: Time.current, updated_at: Time.current
      }])
    end.to raise_error(ActiveRecord::StatementInvalid)
  end
end
