require "rails_helper"

RSpec.describe "Profile", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-profile") }
  let!(:admin) do
    User.create!(organization:, name: "Ada Admin", email: "profile-admin@example.test",
                 password: "long-enough-password", role: :organization_admin)
  end
  let!(:staff_member) do
    User.create!(organization:, name: "Sam Staff", email: "profile-staff@example.test",
                 password: "long-enough-password", role: :production_staff)
  end

  it "lets someone rename themselves without being an administrator" do
    sign_in staff_member
    patch "/api/v1/profile", params: { profile: { name: "Samantha Staff" } }

    expect(response).to have_http_status(:ok)
    expect(staff_member.reload.name).to eq("Samantha Staff")
  end

  # The point of the endpoint: what you may do is decided for you, not by you.
  it "ignores a role or status supplied by the person themselves" do
    sign_in staff_member
    patch "/api/v1/profile", params: { profile: { name: "Sam", role: "organization_admin", status: "suspended" } }

    expect(response).to have_http_status(:ok)
    expect(staff_member.reload).to have_attributes(role: "production_staff", status: "active")
  end

  it "requires the current password before changing it" do
    sign_in staff_member
    patch "/api/v1/profile", params: {
      profile: { password: "a-brand-new-password", password_confirmation: "a-brand-new-password", current_password: "wrong" }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(staff_member.reload.valid_password?("long-enough-password")).to be(true)
  end

  it "changes the password when the current one is given" do
    sign_in staff_member
    patch "/api/v1/profile", params: {
      profile: {
        password: "a-brand-new-password", password_confirmation: "a-brand-new-password",
        current_password: "long-enough-password"
      }
    }

    expect(response).to have_http_status(:ok)
    expect(staff_member.reload.valid_password?("a-brand-new-password")).to be(true)
  end

  it "refuses an unauthenticated request" do
    patch "/api/v1/profile", params: { profile: { name: "Nobody" } }

    expect(response).to have_http_status(:unauthorized)
  end

  describe "the staff screen" do
    it "still refuses a non-administrator changing someone else's role" do
      sign_in staff_member
      patch "/api/v1/staff/#{admin.id}", params: { staff_member: { role: "production_staff" } }

      expect(response).to have_http_status(:forbidden)
      expect(admin.reload.role).to eq("organization_admin")
    end

    it "still lets an administrator change a role" do
      sign_in admin
      patch "/api/v1/staff/#{staff_member.id}", params: { staff_member: { role: "manager" } }

      expect(response).to have_http_status(:ok)
      expect(staff_member.reload.role).to eq("manager")
    end

    # Self-edit on the profile endpoint must not become self-promotion here.
    it "still refuses someone changing their own role on the staff screen" do
      sign_in admin
      patch "/api/v1/staff/#{admin.id}", params: { staff_member: { role: "manager" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(admin.reload.role).to eq("organization_admin")
    end
  end
end
