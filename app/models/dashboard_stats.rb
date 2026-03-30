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
      trendDescription: "Currently open incidents",
      detail: "Across all severity levels"
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
      label: "MTTR",
      value: avg ? "#{avg} min" : "N/A",
      trendDescription: "Mean time to resolve",
      detail: "Across all resolved incidents"
    }
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
      detail: "All severity levels"
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
      trendDescription: "P1 severity this month",
      detail: "Highest severity incidents"
    }
  end

  def beginning_of_month
    @beginning_of_month ||= Time.current.beginning_of_month
  end
end
