require "rails_helper"

RSpec.describe "Staff management", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-staff") }
  let!(:admin) { User.create!(organization:, name: "Admin", email: "admin-staff@example.test", password: "long-enough-password", role: :organization_admin) }
  let!(:manager) { User.create!(organization:, name: "Manager", email: "manager-staff@example.test", password: "long-enough-password", role: :manager) }
  let!(:staff) { User.create!(organization:, name: "Producer", email: "producer-staff@example.test", password: "long-enough-password", role: :production_staff) }

  it "lets an organization admin change a staff role and access status" do
    sign_in admin

    patch "/api/v1/staff/#{staff.id}", params: { staff_member: { role: "manager", status: "suspended" } }

    expect(response).to have_http_status(:ok)
    expect(staff.reload).to have_attributes(role: "manager", status: "suspended")
  end

  it "does not let a manager change team access" do
    sign_in manager

    patch "/api/v1/staff/#{staff.id}", params: { staff_member: { status: "suspended" } }

    expect(response).to have_http_status(:forbidden)
    expect(staff.reload).to be_active
  end

  it "does not let an administrator suspend their own account" do
    sign_in admin

    patch "/api/v1/staff/#{admin.id}", params: { staff_member: { status: "suspended" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(admin.reload).to be_active
  end
end
