class MediaGroup < ApplicationRecord
  # Offered in the UI as one-click chips, because these are the groupings a real
  # estate shoot is almost always divided into.
  SUGGESTED_NAMES = [ "Exterior", "Drone", "Main Floor", "Interior", "Lower Floor", "Upper Floor" ].freeze

  belongs_to :organization
  belongs_to :listing
  has_many :media_assets, dependent: :nullify

  validates :name, presence: true, length: { maximum: 60 }
  validates :name, uniqueness: { scope: :listing_id, case_sensitive: false }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :normalize_name

  scope :ordered, -> { order(:position, :id) }

  private

  def normalize_name
    self.name = name.strip if name.is_a?(String)
  end
end
