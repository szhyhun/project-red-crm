require "rails_helper"

# Board access is the first record-level authorization in this codebase, so the
# cases that matter are the negative ones: who is kept out, and whether a grant
# held through a group behaves like a grant held directly.
RSpec.describe "Board access", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-boards") }
  let!(:other_organization) { Organization.create!(name: "Rival", slug: "rival-boards") }

  let!(:admin) { staff("admin@example.test", :organization_admin) }
  let!(:manager) { staff("manager@example.test", :manager) }
  let!(:developer) { staff("developer@example.test", :production_staff) }
  let!(:outsider) { staff("outsider@example.test", :production_staff) }

  let!(:client_account) { ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent) }
  let!(:client_user) do
    User.create!(organization:, name: "Avery", email: "client@example.test",
                 password: "long-enough-password", role: :client_admin).tap do |user|
      ClientMembership.create!(client_account:, user:)
    end
  end

  let!(:production_board) { organization.default_board }
  let!(:internal_board) do
    organization.boards.create!(name: "CRM Development", kind: "internal", visibility: "restricted",
                                requires_listing: false, client_visible: false, position: 1)
  end

  def staff(email, role)
    User.create!(organization:, name: email.split("@").first.capitalize, email:,
                 password: "long-enough-password", role:)
  end

  def board_slugs
    JSON.parse(response.body).fetch("boards").pluck("slug")
  end

  describe "a restricted board" do
    it "is hidden from an internal user with no grant" do
      sign_in outsider
      get "/api/v1/boards"

      expect(response).to have_http_status(:ok)
      expect(board_slugs).to contain_exactly("production")
    end

    it "is visible to a user granted access directly" do
      internal_board.board_memberships.create!(member: developer, access: "contributor")

      sign_in developer
      get "/api/v1/boards"

      expect(board_slugs).to contain_exactly("production", "crm-development")
    end

    it "is visible through a group the user belongs to" do
      group = organization.user_groups.create!(name: "Developers")
      group.user_group_memberships.create!(user: developer)
      internal_board.board_memberships.create!(member: group, access: "contributor")

      sign_in developer
      get "/api/v1/boards"

      expect(board_slugs).to contain_exactly("production", "crm-development")
    end

    it "becomes invisible again when the user leaves the group" do
      group = organization.user_groups.create!(name: "Developers")
      membership = group.user_group_memberships.create!(user: developer)
      internal_board.board_memberships.create!(member: group, access: "contributor")
      membership.destroy!

      sign_in developer
      get "/api/v1/boards"

      expect(board_slugs).to contain_exactly("production")
    end

    it "is visible to an organization admin without any grant" do
      sign_in admin
      get "/api/v1/boards"

      expect(board_slugs).to contain_exactly("production", "crm-development")
    end

    it "cannot be read directly by a user with no grant" do
      sign_in outsider
      get "/api/v1/boards/#{internal_board.id}"

      expect(response).to have_http_status(:not_found)
    end

    it "cannot have its members changed by a contributor" do
      internal_board.board_memberships.create!(member: developer, access: "contributor")

      sign_in developer
      post "/api/v1/boards/#{internal_board.id}/members",
           params: { member: { member_type: "User", member_id: outsider.id, access: "viewer" } }

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)).to include("error" => "forbidden", "resource" => "Board", "action" => "manage")
    end

    it "lets a granted manager change its members" do
      internal_board.board_memberships.create!(member: manager, access: "manager")

      sign_in manager
      post "/api/v1/boards/#{internal_board.id}/members",
           params: { member: { member_type: "User", member_id: developer.id, access: "contributor" } }

      expect(response).to have_http_status(:created)
      expect(internal_board.board_memberships.count).to eq(2)
    end

    # A manager holds no implicit authority over a board they were not invited
    # to, which is the whole point of a restricted board.
    it "cannot be managed by an ungranted manager" do
      sign_in manager
      patch "/api/v1/boards/#{internal_board.id}", params: { board: { name: "Renamed" } }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "an organization-visible board" do
    it "is manageable by a manager without an explicit grant" do
      sign_in manager
      patch "/api/v1/boards/#{production_board.id}", params: { board: { description: "Shoot pipeline" } }

      expect(response).to have_http_status(:ok)
      expect(production_board.reload.description).to eq("Shoot pipeline")
    end
  end

  describe "client users" do
    it "cannot list boards at all" do
      sign_in client_user
      get "/api/v1/boards"

      expect(response).to have_http_status(:ok)
      expect(board_slugs).to be_empty
    end
  end

  describe "tenancy" do
    it "refuses a grant to a user from another organization" do
      intruder = User.create!(organization: other_organization, name: "Intruder",
                              email: "intruder@example.test", password: "long-enough-password", role: :manager)

      sign_in admin
      post "/api/v1/boards/#{internal_board.id}/members",
           params: { member: { member_type: "User", member_id: intruder.id, access: "manager" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(internal_board.board_memberships).to be_empty
    end
  end

  describe "capabilities" do
    it "reports what the signed-in user may do with each board" do
      internal_board.board_memberships.create!(member: developer, access: "viewer")

      sign_in developer
      get "/api/v1/boards"

      boards = JSON.parse(response.body).fetch("boards").index_by { |board| board["slug"] }
      expect(boards.fetch("crm-development").fetch("capabilities")).to contain_exactly("view")
      expect(boards.fetch("production").fetch("capabilities")).to include("view")
      expect(boards.fetch("production").fetch("capabilities")).not_to include("manage")
    end

    it "reports session-level capabilities on the auth payload" do
      sign_in manager
      get "/api/v1/auth/me"

      capabilities = JSON.parse(response.body).dig("user", "capabilities")
      expect(capabilities.fetch("boards")).to include("create")
      expect(capabilities.fetch("user_groups")).to be_empty
    end
  end
end
