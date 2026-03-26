class DashboardController < InertiaController
  before_action :require_authentication

  def index
    incidents = current_workspace.incidents
      .includes(:incident_status, :incident_severity)
      .where(deleted_at: nil)
      .order(declared_at: :desc)
      .limit(50)

    active_statuses = current_workspace.incident_statuses.live
    active_count = current_workspace.incidents.where(incident_status: active_statuses, deleted_at: nil).count

    resolved_this_month = current_workspace.incidents
      .where(deleted_at: nil)
      .where("resolved_at >= ?", Time.current.beginning_of_month)

    total_this_month = current_workspace.incidents
      .where(deleted_at: nil)
      .where("declared_at >= ?", Time.current.beginning_of_month)
      .count

    critical_severity = current_workspace.incident_severities.find_by(slug: "critical")
    critical_this_month = critical_severity ? current_workspace.incidents
      .where(incident_severity: critical_severity, deleted_at: nil)
      .where("declared_at >= ?", Time.current.beginning_of_month)
      .count : 0

    avg_ttr_minutes = resolved_this_month
      .where.not(resolved_at: nil)
      .pluck(:declared_at, :resolved_at)
      .map { |declared, resolved| ((resolved - declared) / 60.0).round }
      .then { |times| times.any? ? (times.sum / times.size) : nil }

    render inertia: "dashboard/index", props: {
      incidents: incidents.map { |inc|
        lead_assignment = inc.incident_role_assignments
          .joins(:incident_role)
          .find_by(incident_roles: { slug: "incident_lead" })

        {
          id: inc.id,
          identifier: inc.identifier,
          name: inc.name,
          severity: {
            name: inc.incident_severity.name,
            rank: inc.incident_severity.rank
          },
          status: {
            name: inc.incident_status.name,
            lifecycleStage: inc.incident_status.incident_lifecycle_stage.key
          },
          lead: lead_assignment&.workspace_membership&.user&.name,
          declaredAt: inc.declared_at.utc.iso8601,
          resolvedAt: inc.resolved_at&.utc&.iso8601
        }
      },
      stats: [
        {
          label: "Active Incidents",
          value: active_count.to_s,
          change: "",
          changeType: "up",
          trendDescription: "Currently open incidents",
          detail: "Across all severity levels"
        },
        {
          label: "MTTR",
          value: avg_ttr_minutes ? "#{avg_ttr_minutes} min" : "N/A",
          change: "",
          changeType: "down",
          trendDescription: "Mean time to resolve",
          detail: "For incidents resolved this month"
        },
        {
          label: "Total Incidents",
          value: total_this_month.to_s,
          change: "",
          changeType: "up",
          trendDescription: "Declared this month",
          detail: "All severity levels"
        },
        {
          label: "Critical Incidents",
          value: critical_this_month.to_s,
          change: "",
          changeType: "down",
          trendDescription: "P1 severity this month",
          detail: "Highest severity incidents"
        }
      ]
    }
  end
end
