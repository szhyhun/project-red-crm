class CreditTransaction < ApplicationRecord
  belongs_to :organization
  belongs_to :user
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :order, optional: true

  validates :reason, presence: true
  validates :amount_cents, numericality: { only_integer: true, other_than: 0 }
  validates :balance_after_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
