require "rails_helper"

RSpec.describe "Workflow columns", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-columns") }
  let!(:manager) do
    User.create!(
      organization:,
      name: "Morgan Manager",
      email: "columns@example.test",
      password: "long-enough-password",
      role: :manager
    )
  end
  let!(:client) { ClientAccount.create!(organization:, name: "Avery Agent", kind: :agent) }
  let!(:listing) { Listing.create!(organization:, client_account: client, address_line_1: "111 Oak Bay Avenue") }

  before { sign_in manager }

  it "starts each organization with editable default columns" do
    get "/api/v1/workflow_columns"

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).fetch("workflow_columns").pluck("key")).to eq(%w[todo in_progress blocked done])
  end

  it "creates a custom column at the requested position" do
    post "/api/v1/workflow_columns", params: {
      workflow_column: { name: "Client Approval", color: "#ffe599", category: "active", position: 1 }
    }

    expect(response).to have_http_status(:created)
    expect(organization.workflow_columns.find_by!(key: "client_approval")).to be_present
    expect(organization.workflow_columns.ordered.pluck(:key)).to eq(%w[todo client_approval in_progress blocked done])
  end

  it "renames and reorders a custom column without changing its stable key" do
    column = organization.workflow_columns.create!(name: "Client Approval", color: "#ffe599", position: 4)

    patch "/api/v1/workflow_columns/#{column.id}", params: {
      workflow_column: { name: "Customer Review", position: 3 }
    }

    expect(response).to have_http_status(:ok)
    expect(column.reload).to have_attributes(key: "client_approval", name: "Customer Review", position: 3)
    expect(organization.workflow_columns.ordered.pluck(:key)).to eq(%w[todo in_progress blocked client_approval done])
  end

  it "moves existing tasks to the chosen replacement before deleting a column" do
    custom = organization.workflow_columns.create!(name: "Quality Check", color: "#aec7f7", position: 4)
    replacement = organization.workflow_columns.find_by!(key: "done")
    task = WorkflowTask.create!(organization:, listing:, title: "Final QA", stage: "review", status: custom.key)

    delete "/api/v1/workflow_columns/#{custom.id}", params: { replacement_column_id: replacement.id }

    expect(response).to have_http_status(:no_content)
    expect(task.reload.status).to eq("done")
    expect(task.completed_at).to be_present
    expect(WorkflowColumn.exists?(custom.id)).to be(false)
  end
end
