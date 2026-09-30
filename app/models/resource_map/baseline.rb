# What normal looks like for one metric of one resource, over the last week: the typical value (the median), the high
# end of normal (95% of readings fall under it) and the peak. It is read once a day from the provider's own metrics,
# never estimated, so a check or Halon can tell an unusual reading from an ordinary one.
class ResourceMap::Baseline < ApplicationRecord
  self.table_name = "resource_map_baselines"

  WINDOW = 7.days
  HIGH_PERCENTILE = 0.95
  # A baseline no sweep has renewed for this long is about a resource or metric nobody reads any more, so it is not shown.
  FRESH_FOR = 2.days

  # One metric as a provider read it, for the resource its key names, as [time, value] points.
  Found = Data.define(:key, :metric, :label, :unit, :points)

  belongs_to :workspace
  belongs_to :resource, class_name: "ResourceMap::Resource"

  scope :fresh, -> { where(window_to: FRESH_FOR.ago..) }

  # Replaces the swept resources' baselines with what was read now. A metric no longer read, on a resource that was
  # read, goes. A resource the provider could not read keeps its baselines until they are no longer fresh.
  def self.record!(workspace, resources, found, window_from:, window_to:)
    by_key = resources.index_by(&:key)
    now = Time.current
    rows = found.filter_map do |reading|
      resource = by_key[reading.key]
      values = reading.points.map(&:last).compact.sort
      next if resource.nil? || values.empty?

      { workspace_id: workspace.id, resource_id: resource.id, metric: reading.metric, label: reading.label, unit: reading.unit,
        typical: percentile(values, 0.5), high: percentile(values, HIGH_PERCENTILE), peak: values.last, points: values.size,
        window_from: window_from, window_to: window_to, created_at: now, updated_at: now }
    end
    transaction do
      rows.group_by { |row| row[:resource_id] }.each do |resource_id, kept|
        where(resource_id: resource_id).where.not(metric: kept.map { |row| row[:metric] }).delete_all
      end
      upsert_all(rows, unique_by: %i[resource_id metric]) if rows.any?
    end
    rows.size
  end

  # Interpolated between the two nearest readings, so the median of an even count is the middle of its two middle ones.
  def self.percentile(sorted, rank)
    position = (sorted.size - 1) * rank
    lower = sorted[position.floor]
    lower + ((sorted[position.ceil] - lower) * (position - position.floor))
  end

  # How a person or Halon reads it, such as "Requests: usually 12 requests/s, 95% of readings under 30 requests/s, peak 55 requests/s".
  def line
    "#{label}: usually #{typical_text}, 95% of readings under #{high_text}, peak #{peak_text}, " \
      "over the #{((window_to - window_from) / 1.day).round} days to #{window_to.to_date.iso8601}"
  end

  def typical_text = amount(typical)
  def high_text = amount(high)
  def peak_text = amount(peak)

  private

  def amount(value) = [ value.round(value.abs < 10 ? 2 : 0).to_s.sub(/\.0\z/, ""), unit ].compact_blank.join(" ")
end
