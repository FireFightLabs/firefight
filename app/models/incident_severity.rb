class IncidentSeverity < ApplicationRecord
  include ConfigurableOption
  include DefaultableOption

  has_many :incidents, dependent: :restrict_with_error

  NOUN = "severity".freeze
  SLUG_CRITICAL = "critical"

  validates :rank, presence: true, numericality: { only_integer: true, greater_than: 0 }

  # rank is derived from position on every reorder, so a new row only needs a
  # value that passes validation until the renumber lands.
  before_validation :ensure_rank, on: :create

  scope :by_rank, -> { order(rank: :desc) } # Highest severity first
  scope :default_severity, -> { active.find_by(is_default: true) }

  # The severity a picker preselects: the workspace default, or the least
  # severe when none is marked. One rule, so pickers cannot invent their own
  # fallback.
  def self.preselected(severities)
    severities.find(&:is_default?) || severities.last
  end

  # Position is the source of truth for how severe a severity is. First in the
  # list is the most severe. rank is a derived mirror kept in step so existing
  # consumers (the public API, `/firefight list` ordering) keep working and can
  # never drift from the order the settings screen shows.
  def self.position_columns(index, total)
    { position: index + 1, rank: total - index }
  end

  # Rank is what orders severities, so it travels with one wherever it is
  # reported.
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
