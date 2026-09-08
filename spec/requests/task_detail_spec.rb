require "rails_helper"

RSpec.describe "Task detail", type: :request do
  let!(:organization) { Organization.create!(name: "ProjectRed", slug: "projectred-task-detail") }
  let!(:manager) { staff("detail-manager@example.test", :manager) }
  let!(:editor) { staff("detail-editor@example.test", :production_staff) }
  let!(:outsider) { staff("detail-outsider@example.test", :production_staff) }
  let!(:board) do
    organization.boards.create!(name: "CRM Development", kind: "internal", visibility: "restricted",
                                requires_listing: false, client_visible: false, position: 1).tap do |created|
      WorkflowColumn::DEFAULTS.each { |attributes| created.workflow_columns.create!(attributes.merge(organization:)) }
      created.board_memberships.create!(member: editor, access: "contributor")
    end
  end
  let!(:task) do
    board.workflow_tasks.create!(organization:, title: "Ship task detail", status: "todo")
  end

  def staff(email, role)
    User.create!(organization:, name: email.split("@").first, email:,
                 password: "long-enough-password", role:)
  end

  describe "comments" do
    it "lets a contributor comment and returns the author" do
      sign_in editor
      post "/api/v1/workflow_tasks/#{task.id}/comments", params: { task_comment: { body: "Picking this up." } }

      expect(response).to have_http_status(:created)
      comment = JSON.parse(response.body).fetch("task_comment")
      expect(comment).to include("body" => "Picking this up.")
      expect(comment.dig("author", "id")).to eq(editor.id)
    end

    it "refuses a comment from someone with no access to the board" do
      sign_in outsider
      post "/api/v1/workflow_tasks/#{task.id}/comments", params: { task_comment: { body: "Sneaking in." } }

      expect(response).to have_http_status(:not_found)
      expect(task.task_comments).to be_empty
    end

    it "allows commenting through an accessible shared placement" do
      shared_editor = staff("detail-shared-editor@example.test", :production_staff)
      shared_board = organization.boards.create!(name: "Shared detail board", kind: "internal", visibility: "restricted",
                                                  requires_listing: false, client_visible: false, position: 2).tap do |created|
        WorkflowColumn::DEFAULTS.each { |attributes| created.workflow_columns.create!(attributes.merge(organization:)) }
        created.board_memberships.create!(member: shared_editor, access: "contributor")
      end
      task.workflow_task_placements.create!(board: shared_board,
                                            workflow_column: shared_board.workflow_columns.find_by!(key: "todo"),
                                            position: 0)

      sign_in shared_editor
      post "/api/v1/workflow_tasks/#{task.id}/comments", params: { task_comment: { body: "Shared-board note." } }

      expect(response).to have_http_status(:created)
      expect(task.task_comments.reload.pluck(:body)).to include("Shared-board note.")
    end

    it "lets an author edit their own comment and marks it edited" do
      comment = task.task_comments.create!(author: editor, body: "First take")

      sign_in editor
      patch "/api/v1/workflow_tasks/#{task.id}/comments/#{comment.id}",
            params: { task_comment: { body: "Second take" } }

      expect(response).to have_http_status(:ok)
      expect(comment.reload.body).to eq("Second take")
      expect(comment.edited_at).to be_present
    end

    it "sanitizes rich content and supports replies" do
      parent = task.task_comments.create!(author: editor, body: "Parent comment")

      sign_in editor
      post "/api/v1/workflow_tasks/#{task.id}/comments",
           params: { task_comment: { body_html: "<p><strong>Reply</strong></p><script>alert('x')</script>", parent_comment_id: parent.id } }

      expect(response).to have_http_status(:created)
      reply = JSON.parse(response.body).fetch("task_comment")
      expect(reply).to include("body" => "Reply", "parent_comment_id" => parent.id)
      expect(reply.fetch("body_html")).to include("<strong>Reply</strong>")
      expect(reply.fetch("body_html")).not_to include("script")
    end

    it "rejects a reply to another reply" do
      parent = task.task_comments.create!(author: editor, body: "Parent comment")
      reply = task.task_comments.create!(author: editor, parent_comment: parent, body: "First reply")

      sign_in editor
      post "/api/v1/workflow_tasks/#{task.id}/comments",
           params: { task_comment: { body: "Nested reply", parent_comment_id: reply.id } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).dig("details", "parent_comment")).to include("cannot be a reply")
      expect(task.task_comments.where(body: "Nested reply")).to be_empty
    end

    it "refuses to let one person edit another's comment" do
      comment = task.task_comments.create!(author: editor, body: "Mine")
      board.board_memberships.create!(member: manager, access: "manager")

      sign_in manager
      patch "/api/v1/workflow_tasks/#{task.id}/comments/#{comment.id}",
            params: { task_comment: { body: "Rewritten" } }

      expect(response).to have_http_status(:forbidden)
      expect(comment.reload.body).to eq("Mine")
    end

    # Editing someone else's words and removing them are different powers.
    it "lets a board manager delete another person's comment" do
      comment = task.task_comments.create!(author: editor, body: "Off topic")
      board.board_memberships.create!(member: manager, access: "manager")

      sign_in manager
      delete "/api/v1/workflow_tasks/#{task.id}/comments/#{comment.id}"

      expect(response).to have_http_status(:no_content)
      expect(TaskComment.exists?(comment.id)).to be(false)
    end
  end

  describe "checklist items" do
    it "appends an item and records who completed it" do
      sign_in editor
      post "/api/v1/workflow_tasks/#{task.id}/checklist_items",
           params: { task_checklist_item: { title: "Write the migration" } }
      item_id = JSON.parse(response.body).dig("task_checklist_item", "id")

      patch "/api/v1/workflow_tasks/#{task.id}/checklist_items/#{item_id}",
            params: { task_checklist_item: { done: true } }

      expect(response).to have_http_status(:ok)
      item = JSON.parse(response.body).fetch("task_checklist_item")
      expect(item).to include("done" => true)
      expect(item.dig("completed_by", "id")).to eq(editor.id)
    end

    it "clears the completer when an item is unticked" do
      item = task.task_checklist_items.create!(title: "Draft specs", completed_at: Time.current, completed_by: editor)

      sign_in editor
      patch "/api/v1/workflow_tasks/#{task.id}/checklist_items/#{item.id}",
            params: { task_checklist_item: { done: false } }

      expect(item.reload.completed_at).to be_nil
      expect(item.completed_by).to be_nil
    end

    it "refuses an item from someone with no access to the board" do
      sign_in outsider
      post "/api/v1/workflow_tasks/#{task.id}/checklist_items",
           params: { task_checklist_item: { title: "Not mine" } }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the detail payload" do
    it "carries comments, checklist and labels" do
      backend = board.board_labels.create!(name: "backend", color: "#e8f0ff")
      schema = board.board_labels.create!(name: "schema", color: "#f1eafa")
      task.board_labels = [ backend, schema ]
      task.save!
      task.task_comments.create!(author: editor, body: "Started")
      task.task_checklist_items.create!(title: "Migration", position: 0, completed_at: Time.current, completed_by: editor)
      task.task_checklist_items.create!(title: "Specs", position: 1)

      sign_in editor
      get "/api/v1/workflow_tasks/#{task.id}"

      detail = JSON.parse(response.body).fetch("workflow_task")
      expect(detail.fetch("labels").map { |label| label.fetch("name") }).to contain_exactly("backend", "schema")
      expect(detail.fetch("comments").length).to eq(1)
      expect(detail.fetch("checklist_items").pluck("title")).to eq(%w[Migration Specs])
      expect(detail).to include("checklist_total" => 2, "checklist_done" => 1, "comment_count" => 1)
    end

    it "includes rich descriptions, nested replies and activity history" do
      parent = task.task_comments.create!(author: editor, body: "Parent comment")
      reply = task.task_comments.create!(author: editor, parent_comment: parent, body: "Reply comment")
      task.update!(description_html: "<p><em>Detailed scope</em></p><script>bad()</script>")
      ActivityEvent.create!(organization:, actor: editor, subject: task, event_type: "workflow_task.updated", payload: { "status" => "todo" })

      sign_in editor
      get "/api/v1/workflow_tasks/#{task.id}"

      detail = JSON.parse(response.body).fetch("workflow_task")
      expect(detail.fetch("description_html")).to include("<em>Detailed scope</em>")
      expect(detail.fetch("description_html")).not_to include("script")
      expect(detail.dig("comments", 0, "replies", 0)).to include("id" => reply.id, "parent_comment_id" => parent.id)
      expect(detail.fetch("activity").map { |event| event.fetch("event_type") }).to include("workflow_task.updated")
    end

    # The board index shows how much detail a card carries without loading it.
    it "sends counts rather than contents on the index" do
      task.task_comments.create!(author: editor, body: "Started")

      sign_in editor
      get "/api/v1/boards/#{board.id}/workflow_tasks"

      row = JSON.parse(response.body).fetch("workflow_tasks").first
      expect(row).to include("comment_count" => 1)
      expect(row).not_to have_key("comments")
    end
  end
end
