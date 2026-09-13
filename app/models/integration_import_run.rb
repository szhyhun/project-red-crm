class IntegrationImportRun < ApplicationRecord
  STALE_AFTER = 15.minutes

  belongs_to :integration_connection
  belongs_to :organization
  has_many :external_records, dependent: :nullify

  enum :status, { pending: "pending", running: "running", completed: "completed", completed_with_errors: "completed_with_errors", failed: "failed" }, validate: true
  enum :conflict_resolution, { skip: "skip", overwrite: "overwrite" }, validate: true

  validates :provider, presence: true
  validate :import_end_date_on_or_after_start_date

  def terminal?
    completed? || completed_with_errors? || failed?
  end

  def heartbeat!
    return self unless running?

    update_columns(heartbeat_at: Time.current, updated_at: Time.current)
    self
  end

  def stale?(at: Time.current)
    return false unless running?

    last_activity_at = heartbeat_at || started_at || updated_at
    last_activity_at.blank? || last_activity_at < at - STALE_AFTER
  end

  def mark_failed!(message, counts: nil, coverage: nil, error_details: nil, at: Time.current)
    with_lock do
      return self if terminal?

      existing_errors = Array(self.error_details)
      failure_message = message.to_s
      attributes = {
        status: :failed,
        phase: "failed",
        completed_at: at,
        heartbeat_at: at,
        error_details: [ *existing_errors, *Array(error_details), failure_message ].uniq
      }
      attributes[:counts] = counts if counts
      attributes[:coverage] = coverage if coverage
      update!(attributes)
    end
    self
  end

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
