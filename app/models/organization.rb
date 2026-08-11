class Organization < ApplicationRecord
  has_many :users, dependent: :restrict_with_error
  has_many :client_accounts, dependent: :destroy
  has_many :products, dependent: :destroy
  has_many :catalog_sync_runs, dependent: :destroy
  has_many :listings, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_many :appointments, dependent: :destroy
  has_many :workflow_tasks, dependent: :destroy
  has_many :media_assets, dependent: :destroy
  has_many :activity_events, dependent: :destroy
  has_many :invoices, dependent: :destroy

  validates :name, :slug, presence: true
  validates :slug, format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }
end
