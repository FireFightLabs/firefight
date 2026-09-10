class IncidentSeverity < ApplicationRecord
  include ConfigurableOption
  include DefaultableOption

  has_many :incidents, dependent: :restrict_with_error

  NOUN = "severity".freeze
  SLUG_CRITICAL = "critical"

  validates :rank, presence: true, numericality: { only_integer: true, greater_than: 0 }

  # rank is derived from position on reorder, so a new row only needs a
  # value that passes validation until then.
  before_validation :ensure_rank, on: :create

  scope :by_rank, -> { order(rank: :desc) } # Highest severity first
  scope :default_severity, -> { active.find_by(is_default: true) }

  # One rule so pickers cannot invent their own fallback.
  def self.preselected(severities)
    severities.find(&:is_default?) || severities.last
  end

  # First in the list is the most severe. rank mirrors position for the
  # public API and list ordering, so it can never drift from the settings screen.
  def self.position_columns(index, total)
    { position: index + 1, rank: total - index }
  end

  def config_extras
    { rank: rank }
  end

  def more_severe_than?(other_severity)
    rank > other_severity.rank
  end

  def less_severe_than?(other_severity)
    rank < other_severity.rank
  end

  private

  def ensure_rank
    self.rank ||= 1
  end
end
