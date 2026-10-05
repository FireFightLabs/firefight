# enabled is the admin's allowlist, removed_at is whether the provider still offers it.
# Discovery only writes removed_at, so a tool that vanishes and returns keeps the admin's choice.
class Integration::Tool < ApplicationRecord
  belongs_to :integration
  has_one :ability_action, class_name: "Ability::Action", as: :source, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :integration_id },
                   format: { with: /\A[a-z0-9_.]+\z/ }

  scope :enabled, -> { where(enabled: true) }
  scope :available, -> { where(removed_at: nil) }
  scope :in_workspace, ->(workspace) {
    enabled.available.joins(:integration)
      .where(integrations: { workspace_id: workspace.id, disabled_at: nil, deleted_at: nil })
      .includes(:integration, :ability_action)
  }

  # Synced on every mirrored attribute, a stale risk_level on the action
  # would silently stop risk-based approval policies from matching.
  after_save :sync_ability_action!, if: :ability_action_stale?

  def action_key
    "#{integration.slug}.#{name}"
  end

  # A call the resource map's sweep makes. The sweep is not a person and holds no grants, so it calls only tools an admin
  # switched on, and each call is recorded under the map sweep with what it read, never the script. Returns the block's result.
  def swept!(arguments, reads = nil, &)
    recorded!(SystemAgent.map_sweep, AbilityGateway::SOURCE_MAP_SWEEP, arguments, reads, &)
  end

  # A call the health check makes to see that a connection reaches the account behind its server. Like the sweep it
  # calls only tools an admin switched on, and each call is recorded under the health check.
  def checked!(arguments, reads = nil, &)
    recorded!(SystemAgent.health_check, AbilityGateway::SOURCE_HEALTH_CHECK, arguments, reads, &)
  end

  # A tool name cannot carry the dot an action key separates on.
  def model_facing_name
    action_key.tr(".", "_")
  end

  ENVIRONMENT_ARG = "environment".freeze

  # The schema every caller is handed, the agent and an outside MCP client alike: the tool's own, plus
  # which environment to run in. A connection wired per environment lists them, so a model picks one that exists.
  def offered_schema
    schema = (params_schema.presence || { "type" => "object" }).deep_dup
    choices = integration.environment_choices
    environment = { "type" => "string", "description" => "Environment slug, such as production. Omit when the connection has one environment." }
    environment["enum"] = choices if choices.any?
    schema["properties"] = (schema["properties"] || {}).merge(ENVIRONMENT_ARG => environment)
    schema
  end

  # Whether it is worth offering. Each call is still authorized on its own.
  def callable_by?(principal, resolved = Ability::Resolver.resolve(principal, integration.workspace))
    return true if resolved.action_keys.include?(action_key)

    ability_action.present? && principal.implicitly_allowed?(ability_action)
  end

  def available?
    removed_at.nil?
  end

  def toggle_blocked_reason
    return if available?

    "The provider no longer offers this capability. Refresh the tools to check again."
  end

  def configured_for?(scope)
    return false unless enabled? && available? && integration.operational?

    integration.resolve_environment(scope["environment"] || scope[:environment]).present?
  end

  def remote_name
    spec["tool_name"].presence || name
  end

  def sync_ability_action!
    return unless enabled?

    action = Ability::Action.find_or_initialize_by(workspace_id: integration.workspace_id, key: action_key)
    action.assign_attributes(
      kind: Ability::Action::KIND_TOOL,
      risk_level: read_only? ? Ability::Action::RISK_READ : Ability::Action::RISK_WRITE,
      reversible: read_only?,
      params_schema: params_schema,
      source: self
    )
    action.save!
    action
  end

  private

  def ability_action_stale?
    saved_change_to_enabled? || saved_change_to_read_only? || saved_change_to_params_schema?
  end

  def recorded!(principal, source, arguments, reads)
    invocation = AbilityGateway.record!(
      decision: Ability::Invocation::DECISION_ALLOW, completed_at: nil, principal: principal,
      action: Ability::Action.lookup(action_key, integration.workspace), action_key: action_key, workspace: integration.workspace,
      scope: {}, params: arguments.to_h.except("code").merge({ "reads" => reads }.compact), context: { source: source }
    )
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = yield
    failed = result.is_a?(Hash) && result["isError"]
    said = failed ? Ability::Invocation.summary_of(Array(result["content"]).filter_map { |part| part["text"] }.join("\n")) : nil
    invocation.finalize!(outcome: failed ? Ability::Invocation::OUTCOME_ERROR : Ability::Invocation::OUTCOME_SUCCESS, error_summary: said,
                         duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
    result
  rescue StandardError => error
    invocation&.finalize!(outcome: Ability::Invocation::OUTCOME_ERROR, error_summary: error.class.name)
    raise
  end
end
