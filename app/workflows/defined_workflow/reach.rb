# What a workflow's own identity needs granted to run a step, read from what the step calls, so publishing can say
# exactly what the workflow will be able to do and an admin grants it in one step. A read through a connection is that
# connection's read pack, which keeps up with the tools it adds. A change is the one ability it calls. Firefight's own
# tools are their system ability.
module DefinedWorkflow::Reach
  # One grant: either an ability (action) or a connection's read pack (role). key tells them apart in a list.
  Needed = Data.define(:key, :label, :action, :role) do
    def self.of_action(action)
      new(key: action.key, label: DefinedWorkflow::Reach.label_of(action), action: action, role: nil)
    end

    def self.of_role(role)
      new(key: "role:#{role.id}", label: "Read #{role.integration&.display_name || role.name}", action: nil, role: role)
    end

    def target = role ? { role: role } : { action: action }

    def held_by?(principal, workspace, resolved)
      return false unless principal
      return resolved.covers?(Ability::Role.reads_key(role.integration_id)) || role.actions.all? { |action| resolved.covers?(action.key) } if role

      principal.permitted_to?(action, workspace, resolved: resolved)
    end
  end

  # Capability tools a run reaches through the map, so the identity reads the map too.
  MAP_READERS = [
    *Integrations::Capabilities::SPECS.values.map(&:tool_name), Integrations::Capabilities::KEY_QUERY_TOOL,
    Integrations::Capabilities::LOG_PATTERNS_TOOL, Chat::Tools::WhatChanged::NAME
  ].freeze

  module_function

  # What a workflow's identity would do with one of Firefight's own abilities, where its key says too little.
  LABELS = {
    Ability::Action.system_key(Ability::Action::RESOURCE_MONITORING, Ability::Action::ACTION_CREATE) => "Raise monitoring notices",
    Ability::Action.system_key(Ability::Action::RESOURCE_MONITORING, Ability::Action::ACTION_READ) => "Read what Halon raised"
  }.freeze

  def label_of(action)
    return LABELS[action.key] if LABELS.key?(action.key)

    described = Ability::Action.described(action.key)
    return described[:title] if described
    return "#{action.source&.integration&.display_name}: #{action.key.split('.', 2).last.humanize(capitalize: false)}" if action.tool?

    resource, verb = action.key.split(".")
    "#{verb.capitalize} #{Ability::Action.label(resource).downcase}"
  end

  # Every tool a step may name: Firefight's own that Halon may call, the capabilities and general reads, and every
  # connection tool, switched on or not, by the name Halon calls it.
  def tool_names(workspace)
    own = firefight_tools.map { |tool_class| tool_class.name_value.to_s }
    own + MAP_READERS + workspace.tool_labels.keys
  end

  def tool_known?(workspace, name) = tool_names(workspace).include?(name.to_s)

  def firefight_tools = FirefightTools.all.reject { |tool_class| Chat::Tools::Groups::NOT_FOR_HALON.include?(tool_class.name_value.to_s) }

  def firefight_tool(name) = firefight_tools.find { |tool_class| tool_class.name_value.to_s == name.to_s }

  def capability(name) = Chat::Tools::Target.capability_spec(name)

  # Whether a call changes something, decided by the tool and, through its read guard, the call itself. A general read
  # (a key query, new log patterns, what changed) only reads.
  def changes?(workspace, name, arguments = {})
    spec = capability(name)
    return spec.writes if spec
    return false if MAP_READERS.include?(name.to_s)

    Chat::Tools.kind(name, workspace, literal(arguments)) == Chat::Tools::KIND_ACT
  end

  # A value still holding a reference cannot be judged until the run fills it, so only what is written out is shown to a
  # read guard. A call it cannot show reads counts as a change.
  def literal(arguments)
    arguments.to_h.reject { |_key, value| Workflow::Version.references_in(value).any? }
  end

  def for_tool(workspace, name, arguments = {})
    name = name.to_s
    if (tool_class = firefight_tool(name))
      action = workspace.ability_for(Ability::Action.system_key(*tool_class.authorization(workspace, arguments.to_h.symbolize_keys)))
      return action ? [ Needed.of_action(action) ] : []
    end
    return capability_reach(workspace, name, arguments) if MAP_READERS.include?(name)

    tool = workspace.connection_tools_by_name[name]
    tool ? connection_reach(workspace, tool, arguments) : []
  end

  def connection_reach(workspace, tool, arguments)
    reads = tool.read_only? || (tool.ability_action && !changes?(workspace, tool.model_facing_name, arguments))
    return [ workspace.read_packs_by_integration[tool.integration_id] ].compact.map { |role| Needed.of_role(role) } if reads

    tool.ability_action ? [ Needed.of_action(tool.ability_action) ] : []
  end

  # A capability, a key query, new log patterns or what changed reaches whichever connection answers it for the resource
  # and connection the run names, routed as the run routes it. With them written out that is one tool, a read through
  # its connection's read pack and a change its one ability. Otherwise every connection that could answer is reached.
  def capability_reach(workspace, name, arguments)
    keys = capability_keys(name)
    offered = Integrations::Capabilities.offered(workspace).select { |spec, _able| keys.include?(spec.key) }
    needed = offered.flat_map do |spec, able|
      reached = routed_tools(workspace, spec, arguments).presence || able
      next reached.filter_map { |tool| workspace.read_packs_by_integration[tool.integration_id] }.uniq.map { |role| Needed.of_role(role) } unless spec.writes

      reached.filter_map(&:ability_action).uniq.map { |action| Needed.of_action(action) }
    end
    map = Ability::Action.lookup(Ability::Action::MAP_READ, workspace)
    (needed + [ (Needed.of_action(map) if map) ].compact).uniq(&:key)
  end

  def capability_keys(name)
    case name.to_s
    when Integrations::Capabilities::KEY_QUERY_TOOL then ResourceMap::KeyQueries::CAPABILITIES_READ
    when Integrations::Capabilities::LOG_PATTERNS_TOOL then [ Integrations::Capabilities::LOGS ]
    when Chat::Tools::WhatChanged::NAME then [ Integrations::Capabilities::HISTORY ]
    else [ capability(name)&.key ].compact
    end
  end

  # The tools a run reaches for the resource and connection written out, as the run routes them. None when the run
  # fills them in later or nothing routes them, so every connection that could answer counts.
  def routed_tools(workspace, spec, arguments)
    given = literal(arguments).stringify_keys
    return [] if given[Integrations::Capabilities::RESOURCE_ARG].blank?

    Integrations::Capabilities.planned_calls(workspace, spec.key, given).map(&:tool).compact
  rescue Integrations::Capabilities::Unroutable, StandardError
    []
  end

  def reads?(action) = action.key.split(".").last == Ability::Action::ACTION_READ

  def read_pack(integration_id) = Ability::Role.find_by(integration_id: integration_id, pack: Ability::Role::PACK_READ)

  # What following a skill reaches: every tool it names, as a read, since a skill step only ever reads.
  def for_skill(workspace, skill)
    skill.tools.flat_map do |handle|
      next for_tool(workspace, handle).select { |needed| needed.role || reads?(needed.action) } if skill.source == Chat::Skill::SOURCE_FIREFIGHT

      workspace.switched_on_tools.select { |tool| tool.integration.provider == skill.source && tool.name == handle }
                       .filter_map { |tool| read_pack(tool.integration_id) }.map { |role| Needed.of_role(role) }
    end.uniq(&:key)
  end
end
