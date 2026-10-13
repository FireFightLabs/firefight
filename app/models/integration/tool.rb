# enabled is whether it is switched on, removed_at is whether the provider still offers it. A tool arrives switched on
# and is an admin's choice from then, so discovery only writes removed_at for a tool it has seen before, and one that
# vanishes and returns keeps that choice.
class Integration::Tool < ApplicationRecord
  belongs_to :integration
  # The action knows the tool it was read through, so asking whether a member reads it by default reads no tool again.
  has_one :ability_action, class_name: "Ability::Action", as: :source, dependent: :destroy, inverse_of: :source

  validates :name, presence: true, uniqueness: { scope: :integration_id },
                   format: { with: /\A[a-z0-9_.]+\z/ }

  scope :enabled, -> { where(enabled: true) }
  scope :available, -> { where(removed_at: nil) }
  # The tools a workspace's connections offer and have switched on, without loading anything else, for a decision that
  # reads only a few columns of each (Chat::Specialists.crowded?).
  scope :switched_on_in, ->(workspace) {
    enabled.available.joins(:integration).where(integrations: { workspace_id: workspace.id, disabled_at: nil, deleted_at: nil })
  }
  scope :in_workspace, ->(workspace) { switched_on_in(workspace).eager_load(:ability_action, integration: :integration_environments) }

  # How long its definition is, as FirefightAi.fits_up_front? counts it, so whether many tools fit is one sum.
  # Counted as a model is handed it (definition_length), not on the tool's own name, description and schema.
  before_save :count_definition_chars, if: -> {
    new_record? || will_save_change_to_name? || will_save_change_to_description? || will_save_change_to_params_schema? || will_save_change_to_spec?
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
  # one (Integrations::Scopes). rows are the connection's enabled environment rows when the caller read them already
  # (Integration#offered_environment_rows).
  def offered_schema(rows = nil)
    schema = (params_schema.presence || { "type" => "object" }).deep_dup
    choices = integration.environment_choices(rows)
    environment = { "type" => "string", "description" => environment_description(rows) }
    environment["enum"] = choices if choices.any?
    schema["properties"] = (schema["properties"] || {}).merge(ENVIRONMENT_ARG => environment).merge(Integrations::Scopes.argument(integration, rows).to_h)
    schema
  end

  # How long a description an agent is handed may be (Chat::Tools::FULL_DESCRIPTION).
  AGENT_DESCRIPTION_LIMIT = 2_000

  # How long the definition a model is handed is, as fits_up_front? counts it: the name it calls the tool by, with its
  # connection's slug, what an agent reads of the tool, cleaned and capped as Chat::Tools.clean does, and the schema it
  # is offered, with the connection's environment and scope arguments. What a turn adds of its own, such as the intent a
  # call that waits for the person asks for, is not counted. The connection's environments are read into rows of their
  # own, never through its integration_environments, which a caller still holding the connection would then read stale.
  def definition_length(rows = integration.offered_environment_rows)
    described = described_for_agents(rows).to_s.gsub(/[[:cntrl:]]/, " ").squish.truncate(AGENT_DESCRIPTION_LIMIT)
    model_facing_name.size + described.size + Integrations::Replicas.offered(self, offered_schema(rows)).to_json.size
  end

  # Names only the environments this connection has, since an example it lacks is what a model then sends.
  def environment_description(rows = nil)
    slugs = integration.environment_slugs(rows)
    return "Leave this out. This connection has one environment." if slugs.empty?

    named = "Environment slug, one of: #{slugs.join(', ')}."
    integration.environment_choices(rows).any? ? named : "#{named} Leave it out for the connection's default."
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

  # Whether discovery found the tool to read, from its server or the registry, kept in spec beside the server's name.
  DECLARED_READ = "declared_read_only".freeze

  def declared_read? = spec[DECLARED_READ] == true

  # An admin marks a tool as a read on a server Firefight cannot know, such as a team's own, and it is then a read
  # everywhere, exactly as if its server had said so. Unmarking it leaves what its server says.
  def mark_read!(read)
    update!(marked_read: read, read_only: read || declared_read?)
  end

  # Whether an admin may mark this tool as a read: one on a server Firefight cannot know, that its server does not
  # already say only reads.
  def read_markable? = IntegrationProvider.find(integration.provider)&.admin_marks_reads == true && !declared_read?

  # What marking the tool as a read, or taking the mark away, does, which the admin confirms.
  def mark_read_words(read)
    if read
      "Halon will call #{name} without asking, approval rules will not hold it, investigations and watches can use it, and " \
        "every member can call it without a grant, as for any tool that only reads. Mark it only if it never changes anything."
    else
      "Halon will ask before each call to #{name} again, approval rules will hold it, and members will need a grant to call it."
    end
  end

  # Why an admin cannot mark this tool as a read, or take the mark away, or nil.
  def mark_read_blocked_reason(read)
    return "#{integration.name}'s server is one Firefight knows, so its tools are marked as it says." unless IntegrationProvider.find(integration.provider)&.admin_marks_reads
    return "The provider no longer offers this capability. Refresh the tools to check again." unless available?
    return "#{integration.name}'s server already says #{name} only reads." if declared_read?
    return "#{name} is already marked as a read." if read && marked_read?

    "#{name} is not marked as a read." if !read && !marked_read?
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
  def access_missing_reason(rows = nil)
    rows ||= integration.integration_environments.select(&:enabled?)
    lacking = rows.flat_map { |row| Integrations::Installations.missing(row, remote_name) }.uniq
    Integrations::Installations.missing_words(rows.first, lacking) if lacking.any?
  end

  # What an agent reads of the tool, led by what it lacks, so a listing cut short still says it.
  def described_for_agents(rows = nil) = [ access_missing_reason(rows), description.presence ].compact.join(" ").presence

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
    minted = action.new_record?
    action.assign_attributes(
      kind: Ability::Action::KIND_TOOL,
      risk_level: read_only? ? Ability::Action::RISK_READ : Ability::Action::RISK_WRITE,
      reversible: read_only?,
      params_schema: params_schema,
      source: self
    )
    action.save!
    Ability::Role.file!(action, integration)
    grant_paging!(action) if minted
    action
  end

  private

  # A tool a page is raised and kept in step through is granted to Firefight paging the first time it is minted, like
  # the investigator's read pack, so a grant an admin later revokes is never given back.
  def grant_paging!(action)
    return unless Integrations::Paging.sync_tools(integration.provider).include?(name)

    Ability::Grant.grant!(workspace: integration.workspace, principal: SystemAgent.paging, target: { action: action })
  end

  def count_definition_chars
    self.definition_chars = definition_length
  end

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
