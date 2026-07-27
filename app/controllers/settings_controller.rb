class SettingsController < InertiaController
  RECENT_ALERTS_LIMIT = 50
  ACTIVITY_LIMIT = 200
  RESOLVED_APPROVALS_LIMIT = 50

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
        current_workspace.incident_severities.ordered.with_incident_counts
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

  def runbooks
    render inertia: "settings/runbooks", props: {
      runbooks: RunbookSettingsSerializer.many(
        current_workspace.runbooks.active.ordered.includes(:runbook_steps, :incident_conditions)
      ),
      incidentTypes: IncidentTypeSettingsSerializer.many(
        current_workspace.incident_types.active.ordered
      ),
      severities: IncidentSeveritySettingsSerializer.many(
        current_workspace.incident_severities.ordered.with_incident_counts
      ),
      customFields: RunbookCustomFieldSerializer.many(
        current_workspace.incident_field_definitions.active.ordered
          .where(field_type: IncidentCondition::SUPPORTED_CUSTOM_FIELD_TYPES)
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
        current_workspace.incident_severities.ordered.with_incident_counts
      )
    }
  end

  # Who may do what: every principal that can hold a grant, the abilities and
  # sets available to hand out, and the environments a grant can be scoped to.
  def permissions
    render inertia: "settings/permissions", props: {
      principals: principal_rows,
      actions: AbilityActionOptionSerializer.many(Ability::Grant.grantable_actions(current_workspace)),
      sets: AbilityRoleSerializer.many(
        current_workspace.ability_roles.order(:name).includes(:grants, :role_actions)
      ),
      environments: EnvironmentOptionSerializer.many(current_workspace.environment_entries),
      canManage: current_membership.admin_access?
    }
  end

  # The gateway ledger: everything agents and API keys did (or were denied),
  # rendered read-only. This is the oversight surface for governed writes.
  def activity
    scope = current_workspace.ability_invocations.order(created_at: :desc)
    scope = scope.where(decision: params[:decision]) if params[:decision].present?

    render inertia: "settings/activity", props: {
      invocations: AbilityInvocationSerializer.many(scope.limit(ACTIVITY_LIMIT)),
      decision: params[:decision].presence
    }
  end

  def approvals
    scope = current_workspace.ability_approvals.order(created_at: :desc)

    render inertia: "settings/approvals", props: {
      pendingApprovals: AbilityApprovalSerializer.many(scope.pending),
      resolvedApprovals: AbilityApprovalSerializer.many(
        scope.where.not(status: Ability::Approval::STATUS_PENDING).limit(RESOLVED_APPROVALS_LIMIT)
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
    scope = current_workspace.api_keys.where(deleted_at: nil)
    scope = scope.where(workspace_membership_id: current_membership.id) unless current_membership.admin_access?

    render inertia: "settings/api-keys", props: {
      apiKeys: ApiKeySerializer.many(scope.ordered.includes(created_by: :user)),
      canManageServiceKeys: current_membership.admin_access?,
      connectedAgents: connected_agents
    }
  end

  def alert_sources
    render inertia: "settings/alert-sources", props: {
      alertSources: AlertSourceSettingsSerializer.many(
        current_workspace.alert_sources.order(:created_at)
      ),
      severities: IncidentSeveritySettingsSerializer.many(
        current_workspace.incident_severities.active.ordered.with_incident_counts
      )
    }
  end

  def alerts
    source = current_workspace.alert_sources.find(params[:source_id]) if params[:source_id].present?
    scope = current_workspace.alerts
      .includes(:alert_source, :incident, matched_policy_rule: :policy)
      .order(last_seen_at: :desc)
    scope = scope.where(alert_source: source) if source
    scope = scope.where(matched_policy_rule_id: params[:rule_id]) if params[:rule_id].present?

    render inertia: "settings/alerts", props: {
      alerts: AlertSettingsSerializer.many(scope.limit(RECENT_ALERTS_LIMIT)),
      alertSources: current_workspace.alert_sources.order(:name).map { |s| { id: s.id, name: s.name } },
      sourceId: source&.id,
      ruleId: params[:rule_id].presence,
      ruleOptions: routing_rule_options(source)
    }
  end

  def alert_routing
    source = current_workspace.alert_sources.find(params[:source_id]) if params[:source_id].present?
    # The policy being edited is the scope's own, never the inherited fallback.
    policy = (source || current_workspace).alert_routing_policy

    render inertia: "settings/alert-routing", props: {
      policy: policy ? AlertRoutingPolicySerializer.one(policy) : nil,
      alertSource: source ? { id: source.id, name: source.name } : nil,
      hasWorkspaceFallback: current_workspace.alert_routing_policy.present?,
      severities: IncidentSeveritySettingsSerializer.many(
        current_workspace.incident_severities.active.ordered.with_incident_counts
      ),
      channels: workspace_channels,
      members: WorkspaceMembershipSerializer.many(
        current_workspace.workspace_memberships.includes(:user)
      ),
      catalogOptions: catalog_condition_options
    }
  end

  private

  # Everything that can hold a grant, in one list: humans, agents, and the
  # service keys. Personal keys are omitted because they resolve to their
  # owner's authority rather than carrying grants of their own.
  def principal_rows
    associations = { ability_grants: [ :action, { role: :role_actions } ] }
    memberships = current_workspace.workspace_memberships.includes(:user, associations)
    agents = current_workspace.agents.active.includes(associations)
    keys = current_workspace.api_keys.where(deleted_at: nil).service.includes(associations)

    (memberships.to_a + agents.to_a + keys.to_a).map { |principal| PrincipalSerializer.one(principal) }
  end

  # MCP clients this member authorized via OAuth consent; one row per
  # application with a live (non-revoked) token or refresh chain.
  def connected_agents
    Doorkeeper::AccessToken
      .where(resource_owner_id: current_membership.id, revoked_at: nil)
      .includes(:application)
      .group_by(&:application)
      .map do |application, tokens|
        {
          id: application.id,
          name: application.name,
          connectedAt: tokens.map(&:created_at).min.utc.iso8601
        }
      end
  end

  # Rule filter options follow the source filter: a selected source offers the
  # rules of its effective policy; no selection offers every routing rule in
  # the workspace, prefixed with its scope.
  def routing_rule_options(source)
    policies =
      if source
        [ source.effective_alert_routing_policy ].compact
      else
        current_workspace.policies.for_domain(Policy::DOMAIN_ALERT_ROUTING).includes(:scoped_to, :policy_rules)
      end

    policies.flat_map do |policy|
      scope_label = policy.scoped_to.respond_to?(:name) ? policy.scoped_to.name : nil
      policy.policy_rules.sort_by(&:priority).map do |rule|
        { id: rule.id, label: [ scope_label, "rule #{rule.priority}", rule_conditions_label(rule) ].compact.join(" · ") }
      end
    end
  end

  def rule_conditions_label(rule)
    return "always matches" if rule.conditions.blank?

    rule.conditions
      .map { |c| [ c["field"], c["operator"].tr("_", " "), Array(c["value"]).join(", ") ].reject(&:blank?).join(" ") }
      .join(" AND ").truncate(60)
  end

  # Catalog entries grouped by system key so condition values on catalog-backed
  # fields are picked, not typed.
  def catalog_condition_options
    CatalogEntry.active.joins(:catalog_type)
      .where(workspace: current_workspace, catalog_types: { system_key: CatalogType::SYSTEM_KEYS })
      .order(:name)
      .pluck("catalog_types.system_key", :slug, :name)
      .group_by(&:first)
      .transform_values { |rows| rows.map { |_, slug, name| { slug: slug, name: name } } }
  end

  # Best-effort: the notify-target picker degrades to a manual ID input when
  # Slack can't be reached.
  def workspace_channels
    WorkspaceAdapter.for(current_workspace).list_channels
  rescue AdapterError
    []
  end

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
