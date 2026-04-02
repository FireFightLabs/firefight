class SettingsController < InertiaController
  before_action :require_authentication

  def index
    redirect_to settings_roles_path
  end

  def roles
    render inertia: "settings/roles", props: {
      roles: IncidentRoleSerializer.many(
        current_workspace.incident_roles.ordered
      )
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
      forms: IncidentFormSettingsSerializer.many(
        current_workspace.incident_forms.ordered.includes(incident_form_fields: [ :incident_conditions, { incident_field_definition: :workspace } ])
      ),
      customFields: IncidentFieldDefinitionSettingsSerializer.many(
        current_workspace.incident_field_definitions.active.ordered
      ),
      incidentTypes: IncidentTypeSettingsSerializer.many(
        current_workspace.incident_types.active.ordered
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
