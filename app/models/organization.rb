class Organization < ApplicationRecord
  has_many :users, dependent: :restrict_with_error
  has_many :client_accounts, dependent: :destroy
  has_many :customer_teams, dependent: :destroy
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
  has_many :activity_events, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :property_sites, dependent: :destroy
  has_many :marketing_materials, dependent: :destroy
  has_many :conversations, dependent: :destroy
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
    board
  end
end
