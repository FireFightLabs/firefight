# What normal looks like for one metric of one resource, over the last week: the typical value (the median), the high
# end of normal (95% of readings fall under it) and the peak. It is read once a day from the provider's own metrics,
# never estimated, so a check or Halon can tell an unusual reading from an ordinary one.
class ResourceMap::Baseline < ApplicationRecord
  self.table_name = "resource_map_baselines"

  WINDOW = 7.days
  HIGH_PERCENTILE = 0.95
  # A baseline no sweep has renewed for this long is about a resource or metric nobody reads any more, so it is not shown.
  FRESH_FOR = 2.days
  # Rates a provider reads per second, which a baseline keeps per minute.
  PER_SECOND = [ "per second", "requests/s", "rps", "/s" ].freeze
  PER_MINUTE = "per minute".freeze

  # One metric as a provider read it, for the resource its key names, as [time, value] points.
  Found = Data.define(:key, :metric, :label, :unit, :points)

  belongs_to :workspace
  belongs_to :resource, class_name: "ResourceMap::Resource"
  # The connection that read it. A platform and an observability tool reading the same resource each keep their own.
  belongs_to :integration_environment

  scope :fresh, -> { where(window_to: FRESH_FOR.ago..) }

  # Replaces the baselines the connection's environment row read before for the swept resources with what it read now.
  # A metric it no longer reads, on a resource it read, goes. A resource it could not read keeps its baselines until
  # they are no longer fresh. Another connection's baselines for the same resource are never touched.
  def self.record!(environment_row, resources, found, window_from:, window_to:)
    by_key = resources.index_by(&:key)
    now = Time.current
    rows = found.filter_map do |reading|
      resource = by_key[reading.key]
      values = reading.points.map(&:last).compact.sort
      next if resource.nil? || values.empty?

      { workspace_id: resource.workspace_id, resource_id: resource.id, integration_environment_id: environment_row.id, metric: reading.metric,
        label: reading.label, unit: reading.unit, typical: percentile(values, 0.5), high: percentile(values, HIGH_PERCENTILE),
        peak: values.last, points: values.size, window_from: window_from, window_to: window_to, created_at: now, updated_at: now }
    end
    transaction do
      rows.group_by { |row| row[:resource_id] }.each do |resource_id, kept|
        where(resource_id: resource_id, integration_environment_id: environment_row.id).where.not(metric: kept.map { |row| row[:metric] }).delete_all
      end
      upsert_all(rows, unique_by: %i[resource_id integration_environment_id metric]) if rows.any?
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

  # The normal a check is read against, such as "usually 80 ms, 95% under 133 ms".
  def normal_text = "usually #{typical_text}, 95% under #{high_text}"

  # A live reading against this normal, in a sentence, such as "Now 412 ms, 3.1x the usual high of 133 ms (usually 80 ms)".
  # A reading in another unit is converted when it is only a rate per second against a rate per minute, and otherwise
  # said and left uncompared. series is how many series the reading is the highest latest value of.
  def compared(value, reading_unit, series: 1)
    now = "Now #{self.class.amount(value, reading_unit)}#{" (the highest of #{series} series)" if series > 1}"
    converted = in_own_unit(value, reading_unit)
    return "#{now}, in other units than its normal (#{unit}), so it is not compared." if converted.nil?

    if converted > high
      above = high.positive? ? "#{(converted / high).round(1)}x the usual high of #{high_text}" : "above the usual high of #{high_text}"
      "#{now}, #{above} (usually #{typical_text})."
    elsif converted >= typical
      "#{now}, within its usual range (#{normal_text})."
    else
      "#{now}, below its usual #{typical_text} (95% under #{high_text})."
    end
  end

  def self.amount(value, unit) = [ value.round(value.abs < 10 ? 2 : 0).to_s.sub(/\.0\z/, ""), unit ].compact_blank.join(" ")

  private

  def amount(value) = self.class.amount(value, unit)

  def in_own_unit(value, reading_unit)
    given = reading_unit.to_s.strip.downcase
    own = unit.to_s.strip.downcase
    return value if given == own
    return value * 60 if own == PER_MINUTE && PER_SECOND.include?(given)

    nil
  end
end
