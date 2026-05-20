class DashboardStats
  def initialize(workspace)
    @workspace = workspace
  end

  def to_a
    [ active_incidents_stat, mttr_stat, total_incidents_stat, critical_incidents_stat ]
  end

  private

  attr_reader :workspace

  def active_incidents_stat
    count = workspace.incidents
      .where(incident_status: workspace.incident_statuses.live, deleted_at: nil)
      .count

    {
      label: "Active Incidents",
      value: count.to_s,
      trendDescription: count.zero? ? "All clear" : "Open now",
      detail: "Across all severities"
    }
  end

  def mttr_stat
    avg = Rails.cache.fetch("dashboard_stats/#{workspace.id}/mttr", expires_in: 24.hours) do
      workspace.incidents
        .where(deleted_at: nil)
        .where.not(resolved_at: nil)
        .pluck(:declared_at, :resolved_at)
        .map { |declared, resolved| ((resolved - declared) / 60.0).round }
        .then { |times| times.any? ? (times.sum / times.size) : nil }
    end

    {
      label: "Avg. Resolution Time",
      value: avg ? format_minutes(avg) : "—",
      trendDescription: avg ? "Avg. to resolve" : "No data yet",
      detail: "Based on resolved incidents"
    }
  end

  # Formats a total minute count into a short duration string:
  # 45 → "45m", 95 → "1h 35m", 2753 → "1d 21h"
  def format_minutes(minutes)
    return "#{minutes}m" if minutes < 60

    hours = minutes / 60
    if hours < 24
      remaining = minutes % 60
      return remaining.zero? ? "#{hours}h" : "#{hours}h #{remaining}m"
    end

    days = hours / 24
    remaining_hours = hours % 24
    remaining_hours.zero? ? "#{days}d" : "#{days}d #{remaining_hours}h"
  end

  def total_incidents_stat
    count = workspace.incidents
      .where(deleted_at: nil)
      .where("declared_at >= ?", beginning_of_month)
      .count

    {
      label: "Total Incidents",
      value: count.to_s,
      trendDescription: "Declared this month",
      detail: "Across all severities"
    }
  end

  def critical_incidents_stat
    critical_severity = workspace.incident_severities.find_by(slug: IncidentSeverity::SLUG_CRITICAL)
    count = if critical_severity
      workspace.incidents
        .where(incident_severity: critical_severity, deleted_at: nil)
        .where("declared_at >= ?", beginning_of_month)
        .count
    else
      0
    end

    {
      label: "Critical Incidents",
      value: count.to_s,
      trendDescription: "Declared this month",
      detail: "Critical severity only",
      highlight: count.positive? ? "danger" : nil
    }
  end

  def beginning_of_month
    @beginning_of_month ||= Time.current.beginning_of_month
  end
end
