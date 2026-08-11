class CatalogSyncRun < ApplicationRecord
  belongs_to :organization

  enum :status, { pending: "pending", running: "running", completed: "completed", failed: "failed" }, validate: true
end
