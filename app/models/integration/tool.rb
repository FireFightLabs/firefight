# enabled is whether it is switched on, removed_at is whether the provider still offers it. A tool arrives switched on
# and is an admin's choice from then, so discovery only writes removed_at for a tool it has seen before, and one that
# vanishes and returns keeps that choice.
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

  # A read Halon makes as someone before it asks them to confirm a call through this tool, such as who started what it
  # would stop. Recorded under the conversation with what it read. Returns the block's result.
  def read_before_asking!(principal, arguments, reads, incident_id: nil, &)
    AbilityGateway.record_unattended!(
      principal: principal, action_key: action_key, workspace: integration.workspace, params: arguments.to_h.merge("reads" => reads),
      context: { source: AbilityGateway::SOURCE_CONVERSATION, incident_id: incident_id }.compact, &
    )
  end

  # A call the health check makes to see that a connection reaches the account behind its server. Like the sweep it
  # calls only tools that are switched on, and each call is recorded under the health check.
  def checked!(arguments, reads = nil, &)
    recorded!(SystemAgent.health_check, AbilityGateway::SOURCE_HEALTH_CHECK, arguments, reads, &)
  end

  # A call the handbook sync makes to read a page it keeps in step. Like the sweep it calls only tools that are switched
  # on, and each call is recorded under the handbook sync.
  def synced!(arguments, reads = nil, &)
    recorded!(SystemAgent.handbook_sync, AbilityGateway::SOURCE_HANDBOOK_SYNC, arguments, reads, &)
  end

  # A tool name cannot carry the dot an action key separates on.
  def model_facing_name
    action_key.tr(".", "_")
  end

  ENVIRONMENT_ARG = "environment".freeze

  # The schema every caller is handed, the agent and an outside MCP client alike: the tool's own, plus
  # which environment to run in. A connection wired per environment lists them, so a model picks one that exists. A
  # connection that reaches several of what its provider names a scope, such as Northflank projects, also takes which
  # one (Integrations::Scopes).
  def offered_schema
    schema = (params_schema.presence || { "type" => "object" }).deep_dup
    choices = integration.environment_choices
    environment = { "type" => "string", "description" => environment_description }
    environment["enum"] = choices if choices.any?
    schema["properties"] = (schema["properties"] || {}).merge(ENVIRONMENT_ARG => environment).merge(Integrations::Scopes.argument(integration).to_h)
    schema
  end

  # Names only the environments this connection has, since an example it lacks is what a model then sends.
  def environment_description
    slugs = integration.environment_slugs
    return "Leave this out. This connection has one environment." if slugs.empty?

    named = "Environment slug, one of: #{slugs.join(', ')}."
    integration.environment_choices.any? ? named : "#{named} Leave it out for the connection's default."
  end

  # Whether it is worth offering. Each call is still authorized on its own. A tool that can also read through its guard
  # is worth offering to whoever may read its connection, and each change through it still needs its own grant. With
  # arguments, whether this one call may be made, so a change through such a tool needs the grant a change does.
  def callable_by?(principal, resolved = Ability::Resolver.resolve(principal, integration.workspace), arguments: nil)
    return true if resolved.action_keys.include?(action_key)
    return false unless ability_action.present?
    return true if principal.implicitly_allowed?(ability_action, resolved)
    return false unless reads_through_guard? && (arguments.nil? || reads_call?(arguments))

    principal.implicitly_allowed?(ability_action, resolved, reads: true) || resolved.action_keys.include?(Ability::Role.reads_key(integration_id))
  end

  # Whether this call only reads, because the tool only reads or its provider's read guard shows the call does.
  def reads_call?(arguments) = Integrations::ReadGuards.read_call?(self, arguments)

  # Whether a guard can tell this tool's reads from its changes.
  def reads_through_guard? = Integrations::ReadGuards.for(self).present?

  def available?
    removed_at.nil?
  end

  def toggle_blocked_reason
    return "The provider no longer offers this capability. Refresh the tools to check again." unless available?
    return if enabled? || namesake.nil?

    "Halon would call this tool #{model_facing_name}, the name #{namesake.integration.display_name}'s #{namesake.name} tool already has. " \
      "Connect this account again under another name to switch it on."
  end

  # What the app installation the connection was made through was not granted that this tool needs, as a sentence a
  # person reads beside it ("Needs Actions read in the GitHub App."), or nil. Each environment's installation is asked,
  # since one connection may reach several.
  def access_missing_reason
    rows = integration.integration_environments.select(&:enabled?)
    lacking = rows.flat_map { |row| Integrations::Installations.missing(row, remote_name) }.uniq
    Integrations::Installations.missing_words(rows.first, lacking) if lacking.any?
  end

  # What an agent reads of the tool, led by what it lacks, so a listing cut short still says it.
  def described_for_agents = [ access_missing_reason, description.presence ].compact.join(" ").presence

  # Another connection's tool Halon would call by the same name, or nil.
  def namesake = integration.tool_namesakes[name]

  def configured_for?(scope)
    return false unless enabled? && available? && integration.operational?

    integration.resolve_environment(scope["environment"] || scope[:environment]).present?
  end

  def remote_name
    spec["tool_name"].presence || name
  end

  # What its change does beyond its risk, which its action answers (Ability::Action#effects).
  def effects = @effects ||= Integrations::Effects.of(self)

  # The tool its provider names as the one that writes a code change, which is handed who asked and what they said.
  def writes_code? = !read_only? && IntegrationProvider.find(integration.provider)&.code_fix_tool == name

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
    Ability::Role.file!(action, integration)
    action
  end

  private

  def ability_action_stale?
    saved_change_to_enabled? || saved_change_to_read_only? || saved_change_to_params_schema?
  end

  def recorded!(principal, source, arguments, reads, &)
    AbilityGateway.record_unattended!(
      principal: principal, action_key: action_key, workspace: integration.workspace,
      params: arguments.to_h.except("code").merge({ "reads" => reads }.compact), context: { source: source },
      failed: ->(result) { Ability::Invocation.summary_of(Array(result["content"]).filter_map { |part| part["text"] }.join("\n")) if result.is_a?(Hash) && result["isError"] }, &
    )
  end
end
