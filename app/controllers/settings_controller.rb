class SettingsController < InertiaController
  before_action :require_authentication

  def index
    redirect_to settings_roles_path
  end

  def roles
    render inertia: "settings/roles", props: {
      roles: IncidentRoleSerializer.many(IncidentRole.all_for_workspace(current_workspace))
    }
  end

  def statuses
    render inertia: "settings/statuses", props: {
      lifecycleStages: build_lifecycle_stages
    }
  end

  def severities
    render inertia: "settings/severities", props: {
      severities: IncidentSeveritySettingsSerializer.many(
        current_workspace.incident_severities.ordered
      )
    }
  end

  def types
    render inertia: "settings/types", props: {
      types: IncidentTypeSettingsSerializer.many(
        current_workspace.incident_types.active.ordered
      )
    }
  end

  def members
    render inertia: "settings/members", props: {
      members: WorkspaceMembershipSerializer.many(
        current_workspace.workspace_memberships.includes(:user).order(:joined_at)
      )
    }
  end

  def custom_fields
    render inertia: "settings/custom-fields", props: {
      customFields: IncidentFieldDefinitionSettingsSerializer.many(
        current_workspace.incident_field_definitions.active.ordered
      ),
      catalogTypes: CatalogTypeOptionSerializer.many(
        current_workspace.catalog_types.active.ordered
      )
    }
  end

  def forms
    render inertia: "settings/forms", props: {
      forms: IncidentFormSettingsSerializer.many(IncidentForm.all_for_workspace(current_workspace)),
      customFields: IncidentFieldDefinitionSettingsSerializer.many(
        current_workspace.incident_field_definitions.active.ordered
      ),
      incidentTypes: IncidentTypeSettingsSerializer.many(
        current_workspace.incident_types.active.ordered
      ),
      severities: IncidentSeveritySettingsSerializer.many(
        current_workspace.incident_severities.ordered
      )
    }
  end

  def webhooks
    render inertia: "settings/webhooks", props: {
      webhooks: WebhookSerializer.many(
        current_workspace.webhooks.ordered
      )
    }
  end

  def api_keys
    render inertia: "settings/api-keys", props: {
      apiKeys: ApiKeySerializer.many(
        current_workspace.api_keys.where(deleted_at: nil).ordered.includes(created_by: :user)
      )
    }
  end

  def alert_sources
    render inertia: "settings/alert-sources", props: {
      alertSources: AlertSourceSettingsSerializer.many(
        current_workspace.alert_sources.order(:created_at)
      ),
      severities: IncidentSeveritySettingsSerializer.many(
        current_workspace.incident_severities.active.ordered
      )
    }
  end

  def alert_routing
    policy = current_workspace.policies.for_domain(Policy::DOMAIN_ALERT_ROUTING).first

    render inertia: "settings/alert-routing", props: {
      policy: policy ? AlertRoutingPolicySerializer.one(policy) : nil,
      severities: IncidentSeveritySettingsSerializer.many(
        current_workspace.incident_severities.active.ordered
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
