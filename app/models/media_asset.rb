class MediaAsset < ApplicationRecord
  belongs_to :organization
  belongs_to :listing, optional: true
  belongs_to :uploaded_by, class_name: "User", optional: true

  enum :kind, { final: "final", raw: "raw", marketing: "marketing" }, validate: true
  enum :status, { pending: "pending", processing: "processing", ready: "ready", failed: "failed" }, validate: true

  validates :storage_key, :filename, :content_type, presence: true
end
