class IncidentSeverity < ApplicationRecord
  include ConfigurableOption

  NOUN = "severity".freeze
  SLUG_CRITICAL = "critical"

  validates :rank, presence: true, numericality: { only_integer: true, greater_than: 0 }

  # rank is derived from position on every reorder, so a new row only needs a
  # value that passes validation until the renumber lands.
  before_validation :ensure_rank, on: :create

  scope :by_rank, -> { order(rank: :desc) } # Highest severity first
  scope :default_severity, -> { active.find_by(is_default: true) }

  # Position is the source of truth for how severe a severity is: first in the
  # list is the most severe. rank is a derived mirror kept in step so existing
  # consumers (the public API, `/firefight list` ordering) keep working and can
  # never drift from the order the settings screen shows.
  def self.position_columns(index, total)
    { position: index + 1, rank: total - index }
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
