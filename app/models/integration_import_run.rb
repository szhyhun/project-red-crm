class IntegrationImportRun < ApplicationRecord
  belongs_to :integration_connection
  belongs_to :organization
  has_many :external_records, dependent: :nullify

  enum :status, { pending: "pending", running: "running", completed: "completed", completed_with_errors: "completed_with_errors", failed: "failed" }, validate: true
  enum :conflict_resolution, { skip: "skip", overwrite: "overwrite" }, validate: true

  validates :provider, presence: true
  validate :import_end_date_on_or_after_start_date

  def increment_count!(key, by = 1)
    update!(counts: counts.merge(key.to_s => counts.fetch(key.to_s, 0).to_i + by))
  end

  def record_error!(message)
    update!(error_details: error_details + [ message.to_s ])
  end

  private

  def import_end_date_on_or_after_start_date
    return unless has_attribute?(:import_start_date) && has_attribute?(:import_end_date)

    start_date = self[:import_start_date]
    end_date = self[:import_end_date]
    return unless start_date && end_date && end_date < start_date

    errors.add(:import_end_date, "must be on or after the import start date")
  end
end
