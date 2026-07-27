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
  #
  # Ids not in ordered_ids keep their relative order at the end, so a partial
  # list cannot silently drop rows.
  def self.reorder!(workspace, ordered_ids)
    scope = workspace.incident_severities
    known = scope.ordered.pluck(:id)
    requested = ordered_ids.map(&:to_s).select { |id| known.include?(id) }
    final = requested + (known - requested)
    return if final.empty?

    transaction do
      # The unique [workspace_id, position] index rules out writing final
      # positions in place, so park every row out of range first.
      scope.update_all("position = -position - 1")
      final.each_with_index do |id, index|
        scope.where(id: id).update_all(position: index + 1, rank: final.size - index)
      end
    end
  end

  # Reads the count attached by with_incident_counts, falling back to a query
  # so a caller that forgot the scope gets a correct answer, not a permissive one.
  def incident_count
    has_attribute?(:incidents_count) ? self[:incidents_count].to_i : incidents.count
  end

  def deletable?
    incident_count.zero?
  end

  def more_severe_than?(other_severity)
    rank > other_severity.rank
  end

  def less_severe_than?(other_severity)
    rank < other_severity.rank
  end
end
