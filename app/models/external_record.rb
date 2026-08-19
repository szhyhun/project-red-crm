class ExternalRecord < ApplicationRecord
  belongs_to :organization
  belongs_to :integration_connection
  belongs_to :integration_import_run, optional: true
  belongs_to :record, polymorphic: true, optional: true

  enum :sync_status, { imported: "imported", pending_media_copy: "pending_media_copy", copied: "copied", failed: "failed" }, validate: true

  validates :provider, :resource_type, :external_id, presence: true
  validates :external_id, uniqueness: { scope: %i[integration_connection_id resource_type] }
end
