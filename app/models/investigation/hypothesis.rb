class Investigation::Hypothesis < ApplicationRecord
  STATUS_OPEN = "open"
  STATUS_SUPPORTED = "supported"
  STATUS_REFUTED = "refuted"
  STATUSES = [ STATUS_OPEN, STATUS_SUPPORTED, STATUS_REFUTED ].freeze

  belongs_to :investigation
  belongs_to :catalog_entry, optional: true
  has_many :steps, class_name: "Investigation::Step", dependent: :nullify, inverse_of: :hypothesis
  has_many :citations, -> { order(:created_at, :id) }, class_name: "Investigation::Citation",
           as: :cited_by, dependent: :destroy, inverse_of: :cited_by

  validates :assertion, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :position, numericality: { only_integer: true, greater_than: 0 }
  validates :confidence,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  scope :ordered, -> { order(:position) }

  # Settling a theory again replaces what it rested on, since the latest reading is the one that stands.
  def cite!(sources)
    citations.destroy_all
    sources.each { |source| citations.create!(source: source) }
  end
end
