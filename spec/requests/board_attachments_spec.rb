require "rails_helper"
require "tempfile"

RSpec.describe "Board attachments", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-board-attachments") }
  let!(:editor) do
    User.create!(organization:, name: "Editor", email: "attachment-editor@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:outsider) do
    User.create!(organization:, name: "Outsider", email: "attachment-outsider@example.test",
                 password: "long-enough-password", role: :production_staff)
  end
  let!(:board) do
    organization.boards.create!(name: "Engineering", kind: "internal", visibility: "restricted",
                                requires_listing: false, client_visible: false, position: 1).tap do |created|
      WorkflowColumn::DEFAULTS.each { |attributes| created.workflow_columns.create!(attributes.merge(organization:)) }
      created.board_memberships.create!(member: editor, access: "contributor")
    end
  end
  let!(:task) { board.workflow_tasks.create!(organization:, title: "Attach design notes", status: "todo") }

  it "keeps attachments on a board-private task" do
    attachment = task.board_attachments.create!(organization:, board:, uploaded_by: editor, status: :ready,
                                                 storage_key: "organizations/#{organization.id}/boards/#{board.id}/private.txt",
                                                 filename: "private.txt", content_type: "text/plain", byte_size: 5)

    sign_in outsider
    get "/api/v1/workflow_tasks/#{task.id}/attachments/#{attachment.id}/download"

    expect(response).to have_http_status(:not_found)
  end

  it "uploads a file and returns authorized routes without the storage key" do
    upload = Tempfile.new([ "design-notes", ".txt" ])
    upload.write("notes")
    upload.rewind
    allow(BoardStorage).to receive(:write)

    sign_in editor
    post "/api/v1/workflow_tasks/#{task.id}/attachments",
         params: { files: [ Rack::Test::UploadedFile.new(upload.path, "text/plain", true, original_filename: "design-notes.txt") ] }

    expect(response).to have_http_status(:created)
    attachment = JSON.parse(response.body).fetch("board_attachments").first
    expect(attachment).to include("filename" => "design-notes.txt", "status" => "ready")
    expect(attachment).not_to have_key("storage_key")
    expect(attachment.fetch("preview_path")).to include("/preview")
  ensure
    upload&.close!
  end

  it "streams an S3 preview through the authorized API origin" do
    attachment = task.board_attachments.create!(organization:, board:, uploaded_by: editor, status: :ready,
                                                 storage_key: "organizations/#{organization.id}/boards/#{board.id}/preview.png",
                                                 filename: "preview.png", content_type: "image/png", byte_size: 5)
    allow(BoardStorage).to receive(:s3?).and_return(true)
    allow(BoardStorage).to receive(:exist?).with(attachment.storage_key).and_return(true)
    allow(BoardStorage).to receive(:stream).with(attachment.storage_key).and_return([ "image" ])

    sign_in editor
    get "/api/v1/workflow_tasks/#{task.id}/attachments/#{attachment.id}/preview"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["Content-Disposition"]).to include("inline")
    expect(response.body).to eq("image")
  end
end
