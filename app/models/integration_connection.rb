class IntegrationConnection < ApplicationRecord
  belongs_to :organization
  has_many :integration_import_runs, dependent: :destroy
  has_many :external_records, dependent: :destroy

  enum :provider, { aryeo: "aryeo" }, prefix: :provider, validate: true
  enum :status, { disconnected: "disconnected", connected: "connected", invalid: "invalid", importing: "importing" }, prefix: :status, validate: true

  encrypts :api_key

  validates :provider, uniqueness: { scope: :organization_id }

  def api_key_configured?
    api_key.present?
  end

  def masked_api_key
    return nil unless api_key_configured?

    "••••••••#{api_key.last(4)}"
  end

  def disconnect!
    update!(api_key: nil, status: :disconnected, credentials_updated_at: Time.current)
  end
end
