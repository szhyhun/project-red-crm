class IntegrationImportRun < ApplicationRecord
  belongs_to :integration_connection
  belongs_to :organization
  has_many :external_records, dependent: :nullify

  enum :status, { pending: "pending", running: "running", completed: "completed", failed: "failed" }, validate: true

  validates :provider, presence: true

  def increment_count!(key, by = 1)
    update!(counts: counts.merge(key.to_s => counts.fetch(key.to_s, 0).to_i + by))
  end

  def record_error!(message)
    update!(error_details: error_details + [message.to_s])
  end
end
