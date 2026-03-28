class SettingsController < InertiaController
  before_action :require_authentication

  def index
    render inertia: "settings/index", props: {
      roles: IncidentRoleSerializer.many(
        current_workspace.incident_roles.ordered
      ),
      lifecycleStages: build_lifecycle_stages,
      severities: IncidentSeveritySettingsSerializer.many(
        current_workspace.incident_severities.ordered
      )
    }
  end

  private

  def build_lifecycle_stages
    statuses_by_stage = current_workspace.incident_statuses
      .ordered
      .includes(:incident_lifecycle_stage)
      .group_by { |s| s.incident_lifecycle_stage.key }

    IncidentLifecycleStage.ordered.map do |stage|
      {
        **LifecycleStageSerializer.one(stage),
        statuses: IncidentStatusSettingsSerializer.many(statuses_by_stage[stage.key] || [])
      }
    end
  end
end
