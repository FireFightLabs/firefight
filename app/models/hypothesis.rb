class Hypothesis < ApplicationRecord
  STATUS_OPEN = "open"
  STATUS_SUPPORTED = "supported"
  STATUS_REFUTED = "refuted"
  STATUSES = [ STATUS_OPEN, STATUS_SUPPORTED, STATUS_REFUTED ].freeze

  belongs_to :investigation
  belongs_to :catalog_entry, optional: true
  has_many :investigation_steps, dependent: :nullify, inverse_of: :hypothesis

  validates :assertion, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :confidence,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  scope :ordered, -> { order(:position) }
end
