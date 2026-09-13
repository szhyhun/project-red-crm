class Organization < ApplicationRecord
  has_many :users, dependent: :restrict_with_error
  has_many :client_accounts, dependent: :destroy
  has_many :products, dependent: :destroy
  has_many :taxes, dependent: :destroy
  has_many :coupons, dependent: :destroy
  has_many :travel_fees, dependent: :destroy
  has_many :pricing_plans, dependent: :destroy
  has_many :catalog_sync_runs, dependent: :destroy
  has_many :integration_connections, dependent: :destroy
  has_many :integration_import_runs, dependent: :destroy
  has_many :external_records, dependent: :destroy
  has_many :listings, dependent: :destroy
  has_many :listing_feedbacks, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :appointments, dependent: :destroy
  has_many :boards, dependent: :destroy
  has_many :user_groups, dependent: :destroy
  has_many :workflow_tasks, dependent: :destroy
  has_many :workflow_columns, dependent: :destroy
  has_many :media_assets, dependent: :destroy
  has_many :media_groups, dependent: :destroy
  has_many :board_attachments, dependent: :destroy
  has_many :activity_events, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :property_sites, dependent: :destroy
  has_many :marketing_materials, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :product_components, dependent: :destroy
  has_many :order_deliverables, dependent: :destroy
  has_many :media_reviews, dependent: :destroy
  has_many :media_review_deliverables, through: :media_reviews
  has_many :media_review_assets, through: :media_reviews
  has_many :media_review_threads, through: :media_reviews
  has_many :media_review_comments, through: :media_review_threads
  has_many :board_workflows, dependent: :destroy
  has_many :board_workflow_runs, dependent: :destroy
  has_many :workflow_task_placements, through: :boards
  has_many :message_media_references, through: :conversations
  has_many :conversation_attachments, dependent: :destroy
  has_many :saved_listing_views, dependent: :destroy

  validates :name, :slug, presence: true
  validates :slug, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }

  after_create :create_default_board

  def default_board
    boards.active.ordered.first
  end

  private

  # Columns cannot exist without a board, so the organization's first board is
  # created with them rather than alongside them.
  def create_default_board
    board = boards.create!(
      name: "Production", slug: "production", kind: "production",
      visibility: "organization", requires_listing: true, client_visible: true, position: 0
    )
    WorkflowColumn::DEFAULTS.each { |attributes| board.workflow_columns.create!(attributes.merge(organization: self)) }
    workflow = board.board_workflows.create!(organization: self, name: "Create production work", is_default: true,
                                             trigger_key: "order_approved", workflow_version: 1, enabled: false)
    workflow.actions.create!(action_type: "create_parent_task", configuration: { "title" => "Production" }, position: 0)
    workflow.actions.create!(action_type: "create_or_group_child_task", configuration: { "customer_visible" => true }, position: 1)
    workflow.actions.create!(action_type: "place_on_board", configuration: { "board_id" => board.id, "column_key" => "todo" }, position: 2)
    BoardWorkflow.default_status_mapping_attributes(board).each do |attributes|
      workflow.status_mappings.create!(attributes)
    end
    workflow.update!(enabled: true)
    board
  end
end
