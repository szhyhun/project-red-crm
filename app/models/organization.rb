class Organization < ApplicationRecord
  has_many :users, dependent: :restrict_with_error
  has_many :client_accounts, dependent: :destroy
  has_many :products, dependent: :destroy
  has_many :catalog_sync_runs, dependent: :destroy
  has_many :listings, dependent: :destroy
  has_many :listing_feedbacks, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :appointments, dependent: :destroy
  has_many :workflow_tasks, dependent: :destroy
  has_many :workflow_columns, dependent: :destroy
  has_many :media_assets, dependent: :destroy
  has_many :activity_events, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :property_sites, dependent: :destroy
  has_many :marketing_materials, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :saved_listing_views, dependent: :destroy

  validates :name, :slug, presence: true
  validates :slug, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }

  after_create :create_default_workflow_columns

  private

  def create_default_workflow_columns
    WorkflowColumn::DEFAULTS.each { |attributes| workflow_columns.create!(attributes) }
  end
end
