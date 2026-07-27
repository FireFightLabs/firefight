class IncidentSeverity < ApplicationRecord
  include Positioned

  SLUG_CRITICAL = "critical"

  belongs_to :workspace
  has_many :incidents, dependent: :restrict_with_error

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: { scope: :workspace_id }
  validates :rank, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :position, presence: true, numericality: { only_integer: true }
  validates :is_default, uniqueness: { scope: :workspace_id, if: :is_default? }

  scope :active, -> { where(deleted_at: nil) }
  scope :ordered, -> { order(:position) }
  # One correlated subquery for the whole page instead of an exists? per row.
  scope :with_incident_counts, -> {
    select(
      "#{table_name}.*",
      "(SELECT COUNT(*) FROM incidents WHERE incidents.incident_severity_id = #{table_name}.id) AS incidents_count"
    )
  }
  scope :by_rank, -> { order(rank: :desc) } # Highest severity first
  scope :default_severity, -> { active.find_by(is_default: true) }

  # Position is the source of truth for how severe a severity is: first in the
  # list is the most severe. rank is a derived mirror kept in step so existing
  # consumers (the public API, `/firefight list` ordering) keep working and can
  # never drift from the order the settings screen shows.
  def self.position_attributes(index, total)
    { position: index + 1, rank: total - index }
  end

  # Reads the count attached by with_incident_counts, falling back to a query
  # so a caller that forgot the scope gets a correct answer, not a permissive one.
  def incident_count
    has_attribute?(:incidents_count) ? self[:incidents_count].to_i : incidents.count
  end

  def deletable?
    incident_count.zero?
  end

  def enabled?
    deleted_at.nil?
  end

  # Exactly one default per workspace, so promoting one demotes the incumbent in
  # the same transaction. A partial unique index backs this up, since the model
  # validation alone cannot stop an update_all or a raw write.
  def make_default!
    self.class.transaction do
      workspace.incident_severities.where(is_default: true).where.not(id: id).update_all(is_default: false)
      update!(is_default: true)
    end
  end

  def more_severe_than?(other_severity)
    rank > other_severity.rank
  end

  def less_severe_than?(other_severity)
    rank < other_severity.rank
  end
end
