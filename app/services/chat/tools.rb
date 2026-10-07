# Everything the agent could reach. The acting principal's permissions decide which entries are callable.
module Chat::Tools
  STATE_READY = :ready
  STATE_NOT_GRANTED = :not_granted
  STATE_NOT_CONNECTED = :not_connected
  STATE_SWITCHED_OFF = :switched_off
  # A tool that can change things, in a run that only reads.
  STATE_READS_ONLY = :reads_only

  # One line is what the agent reads about a tool before it opens it. Another system's words about
  # itself are cut to that and stripped of anything that is not text.
  ONE_LINE = 200
  TITLE_LIMIT = 60
  FULL_DESCRIPTION = 2_000

  # source is whose tool it is, Firefight's own or a provider's key, and handle is the name that source gives it, which a
  # skill names since the name the agent sees depends on the connection.
  Entry = Data.define(:name, :description, :state, :tool, :group, :source, :handle)

  def self.clean(text, limit)
    text.to_s.gsub(/[[:cntrl:]]/, " ").squish.truncate(limit)
  end

  HEADLINE_ARGUMENTS = %w[query name identifier title].freeze
  # Long enough that a command someone is asked to confirm is shown whole. The page wraps it.
  ASKED_LIMIT = 400

  KIND_READ = "read"
  KIND_ACT = "act"

  Step = Data.define(:title, :headline, :asked, :card)

  # A result the page draws as something other than text. The step carries only what to draw, and the page
  # reads the rows from the workspace as they are now, so a card says the truth after the person acts on it.
  Card = Data.define(:kind, :category)
  CARD_INTEGRATIONS = "integrations".freeze
  # The run a chat started. The page finds it by the step's tool call, since the run exists only once the tool has run.
  CARD_INVESTIGATION = "investigation".freeze
  # Charts a tool returned. The page finds them by the step's tool call, since a tool only returns them when it has data.
  CARD_CHART = "chart".freeze
  CARD_KINDS = [ CARD_INTEGRATIONS, CARD_INVESTIGATION, CARD_CHART ].freeze

  def self.chart_card = Card.new(kind: CARD_CHART, category: nil)

  def self.card_for(tool_name, arguments)
    return Card.new(kind: CARD_INVESTIGATION, category: nil) if tool_name.to_s == Mcp::Tools::START_INVESTIGATION
    return nil unless tool_name.to_s == Mcp::Tools::LIST_INTEGRATIONS

    category = arguments.to_h.stringify_keys["category"]
    return nil if category.blank?

    Card.new(kind: CARD_INTEGRATIONS, category: IntegrationProvider.category_for!(category).slug)
  rescue ArgumentError
    nil
  end

  # A tool that only reads is the agent looking something up, which the page shows as thinking rather than as a change.
  def self.kind(tool_name, workspace)
    name = tool_name.to_s
    reading = name == ReadResult.tool_name || [ Web::SEARCH, Web::READ ].include?(name) || firefight_reading_names.include?(name) ||
              workspace.reading_tool_names.include?(name)
    reading ? KIND_READ : KIND_ACT
  end

  def self.firefight_reading_names
    @firefight_reading_names ||= Mcp::Tools.all.filter_map { |tool_class| tool_class.name_value.to_s if tool_class.annotations_value&.read_only_hint }.to_set
  end

  # target is what the call reaches, worked out from the tool when it was asked (Chat::Tools::Target), and call what the
  # tool does, such as "Api request". Both are nil for Firefight's own tools and for calls asked before targets were kept.
  Confirmation = Data.define(:tool_call_id, :question, :intent, :asked, :status, :target, :call)

  # A call that waits for the person's decision carries one sentence saying what it will do, written by the agent for
  # whoever approves it. It is taken off before the call is made, so the tool never sees it.
  INTENT_ARG = "intent".freeze
  INTENT = {
    "type" => "string",
    "description" => "One sentence for the person asked to approve this call: what it will do and why, in plain words, " \
                     "such as \"List the zones in the account to find the one for firefight.app\""
  }.freeze

  def self.with_intent(schema)
    schema = schema.deep_dup
    schema["properties"] = (schema["properties"] || {}).merge(INTENT_ARG => INTENT)
    schema["required"] = (Array(schema["required"]) + [ INTENT_ARG ]).uniq
    schema
  end

  def self.intent_of(arguments) = arguments.to_h.stringify_keys[INTENT_ARG].to_s.strip.presence
  CONFIRMATION_STATUSES = {
    Chat::APPROVAL_REQUESTED => :awaiting, Chat::APPROVAL_APPROVED => :confirmed, Chat::APPROVAL_DENIED => :cancelled
  }.freeze

  # A run that only measures Halon reads memory and never changes it, so nothing it does reaches the Memory page.
  def self.memory(agent_run)
    return [ Recall.new(agent_run) ] unless agent_run.changes_memory?

    [ Remember.new(agent_run), Recall.new(agent_run), DisputeMemory.new(agent_run) ]
  end

  # How the agent writes and finds its way, not what it looked at, so a reader is never shown them.
  def self.internal_names
    @internal_names ||= [
      Open.tool_name, Investigation::Tools::Conclude.tool_name, Investigation::Tools::RecordHypothesis.tool_name
    ].freeze
  end

  # nil for the agent's own bookkeeping, which is never shown. With a workspace, a connection tool is titled by what it
  # does and the connection it runs through, as the confirmation names it.
  def self.step(tool_name, arguments, workspace: nil)
    return nil if tool_name.blank? || internal_names.include?(tool_name.to_s)

    asked = shown_arguments(arguments.to_h.stringify_keys.except(INTENT_ARG))
    Step.new(
      title: title_for(tool_name, workspace), headline: intent_of(arguments) || headline_for(tool_name, asked), asked: asked,
      card: card_for(tool_name, arguments)
    )
  end

  # A tool that takes a whole form in one argument is shown as the form's own fields, so a reader
  # sees the incident's name rather than a hash. Anything else nested is one line of JSON.
  def self.shown_arguments(arguments)
    arguments.to_h.flat_map do |name, value|
      next [] if value.blank?
      next value.to_h.filter_map { |key, inner| [ key.to_s, shown_value(inner) ] if inner.present? } if form?(value)

      [ [ name.to_s, shown_value(value) ] ]
    end
  end

  def self.form?(value) = value.is_a?(Hash) && value.values.all? { |inner| !inner.is_a?(Hash) && !inner.is_a?(Array) }

  def self.shown_value(value)
    text = value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value.to_s
    text.truncate(ASKED_LIMIT)
  end

  # What tells one call from the next. An argument named for what is being looked for comes first,
  # then whatever the tool cannot be called without, so four reads of four forms do not all read the same.
  # The incident is where a step happens, so it names the step only when nothing else tells two apart,
  # and eight resolves in a row read "Resolve incident INC-001" rather than eight of the same.
  LAST_RESORT_HEADLINE = %w[incident].freeze

  def self.headline_for(tool_name, asked)
    # A form's own name field is what tells two declares apart, so it counts before the argument that held the form.
    wanted = (HEADLINE_ARGUMENTS + required_arguments.fetch(tool_name.to_s, [])) - LAST_RESORT_HEADLINE
    (wanted + LAST_RESORT_HEADLINE).filter_map { |name| asked.assoc(name)&.last }.first.to_s
  end

  def self.required_arguments
    @required_arguments ||= Mcp::Tools.all.to_h do |tool_class|
      [ tool_class.name_value.to_s, Array(tool_class.input_schema_value.to_h[:required]).map(&:to_s) ]
    end
  end

  # The person confirmed the call in the chat, so an approval they may give themselves is given, once.
  def self.approve_for_asker(agent_run, approval)
    approval.approve!(by: agent_run.acting_principal)
    ApprovalNotificationService.mark_resolved!(approval)
    true
  rescue Ability::Approval::NotAllowed
    false
  end

  def self.waiting_for_approval(action_key)
    "Needs an approval and was not run: #{action_key}. Carry on with what you can reach and say what you could not check."
  end

  # A call with a target is asked about what it reaches, the call itself and the agent's words coming after, since the
  # agent's words can name another account than the one the tool reaches.
  def self.confirmation(tool_call)
    step = step(tool_call.name, tool_call.arguments)
    target = tool_call.try(:target).presence
    call = (call_title(tool_call) if target)
    Confirmation.new(
      tool_call_id: tool_call.tool_call_id, question: target ? "#{call} on #{target}?" : "#{step&.title || tool_call.name.humanize}?",
      intent: intent_of(tool_call.arguments), asked: step&.asked || [], status: CONFIRMATION_STATUSES.fetch(tool_call.approval, :awaiting),
      target: target, call: call
    )
  end

  # What the tool does, by its own name rather than the connection's, such as "Api request".
  # A connection tool reads as "Api request · Faylee (Northflank)", never as its connection's slug made into words, which
  # reads like the provider's name. Anything else is its own name made into words.
  def self.title_for(tool_name, workspace)
    tool = workspace && Target.connection_tool(workspace, tool_name)
    return tool_name.to_s.tr("_", " ").humanize unless tool

    "#{tool.name.tr('_.', '  ').humanize} · #{tool.integration.display_name}"
  end

  def self.call_title(tool_call)
    workspace = tool_call.message&.chat&.workspace
    tool = workspace && Target.connection_tool(workspace, tool_call.name)
    (tool ? tool.name : tool_call.name).to_s.tr("_.", "  ").humanize
  end

  # A result that fits the running model is handed over whole. A larger one is kept in full and the
  # agent is shown how it starts and ends, with the name to read the rest by.
  def self.hand_over(agent_run, tool_name, outcome)
    chat = agent_run.chat
    text = outcome.value
    return FirefightAi::Evidence.frame(tool_name, text, step: outcome.step) if chat.nil? || text.to_s.length <= chat.result_limit

    saved = chat.saved_results.keep!(tool_name: tool_name, text: text, step: outcome.step)
    preview = FirefightAi::Evidence.preview(text, handle: saved.handle, read_with: ReadResult.tool_name)
    FirefightAi::Evidence.frame(tool_name, preview, step: outcome.step)
  end

  # Read fresh, since a run's chat may have been opened after the run was loaded.
  # A memory write as whoever the agent acts for. A refusal or a wait is text the model reads, and the call is marked.
  # The ledger gets ids and flags only, never the fact, since a fact holding a secret is refused only after.
  # A chat or run working on an incident tells its channel what it learned or disputed, so people can decide on it there.
  # Elsewhere the Memory page's count is the sign.
  def self.tell_incident(agent_run, memory, kind)
    return unless agent_run.changes_memory? && agent_run.incident&.channel_id.present?

    MemoryNoteJob.perform_later(memory.id, kind, agent_run.chat_owner)
  end

  def self.memory_change(agent_run, crud_action, tool_name:, params:, tool_call_id:, &)
    agent_run.memory_change(crud_action, params: params, tool_name: tool_name, &)
  rescue AbilityGateway::Denied => denied
    mark_failed(agent_run, tool_call_id)
    agent_run.refusal(denied.action_key)
  rescue AbilityGateway::PendingApproval
    waiting_for_approval(Ability::Action.system_key(Ability::Action::RESOURCE_MEMORY, crud_action))
  end

  # kind says whether the provider answered that what was asked about is not there (Chat::StepOutcome).
  def self.mark_failed(agent_run, tool_call_id, kind: Chat::StepOutcome::FAILURE_ERROR)
    return if tool_call_id.blank?

    Chat.find_by(owner: agent_run.chat_owner)&.mark_failed!(tool_call_id, kind: kind)
  end

  # What a step is called wherever it is cited later, such as "Get form declare".
  def self.label(tool_name, arguments, workspace: nil)
    shown = step(tool_name, arguments, workspace: workspace)
    [ shown&.title, shown&.headline ].compact_blank.join(" ")
  end

  # What the chat found earlier, for whoever acts now, so a grant taken away since is not handed back.
  def self.known(agent_run, chat)
    names = chat.known_tool_names
    return [] if names.empty?

    ready = catalog(agent_run).select(&:tool).index_by(&:name)
    names.filter_map { |name| ready[name]&.tool }
  end

  # Offered to the live chat and remembered, so a later turn or a resumed run starts with them.
  def self.offer_to(chat)
    lambda do |tools|
      chat.remember_found_tools!(tools.map(&:name))
      chat.with_tools(*tools)
    end
  end

  # The workspace's tools and the principal's grants are read once, since both lists need them.
  def self.catalog(agent_run)
    tools = Integration::Tool.in_workspace(agent_run.workspace).to_a
    resolved = agent_run.acting_principal && granted(agent_run)
    firefight_entries(agent_run) + capability_entries(agent_run, tools: tools, resolved: resolved) +
      connection_entries(agent_run, tools: tools, resolved: resolved)
  end

  def self.firefight_entries(agent_run)
    principal = agent_run.acting_principal
    workspace = agent_run.workspace
    offered = Mcp::Tools.all.reject { |tool_class| Groups::NOT_FOR_HALON.include?(tool_class.name_value.to_s) }
    keys = offered.to_h { |tool_class| [ tool_class, Ability::Action.system_key(*tool_class.authorization(workspace, {})) ] }
    actions = Ability::Action.system_actions.where(key: keys.values).index_by(&:key)

    keys.map do |tool_class, action_key|
      # A run that only reads is never handed one of Firefight's own tools that writes, whatever its principal was granted.
      writes = agent_run.reads_only? && !tool_class.annotations_value&.read_only_hint
      ready = !writes && principal.present? && principal.permitted_to?(actions[action_key], workspace)
      Entry.new(
        name: tool_class.name_value, description: clean(tool_class.description_value, ONE_LINE),
        state: (writes && STATE_READS_ONLY) || (ready ? STATE_READY : STATE_NOT_GRANTED),
        tool: (Firefight.new(agent_run, tool_class, actions[action_key]) if ready),
        group: Groups.of_firefight_tool(tool_class.name_value), source: Chat::Skill::SOURCE_FIREFIGHT, handle: tool_class.name_value.to_s
      )
    end
  end

  def self.connection_entries(agent_run, tools: Integration::Tool.in_workspace(agent_run.workspace).to_a, resolved: nil)
    principal = agent_run.acting_principal
    resolved ||= principal && granted(agent_run)

    # A provider tool a capability answers one to one is reached through the capability, so it is not offered twice,
    # and a connection tool that happens to share a capability's name is left out rather than shadowing it.
    tools.reject { |tool| Integrations::Capabilities.wrapped?(tool) || Integrations::Capabilities.tool_names.include?(tool.model_facing_name) }.map do |tool|
      writes = agent_run.reads_only? && !tool.read_only? && Integrations::ReadGuards.for(tool).nil?
      ready = !writes && principal.present? && tool.callable_by?(principal, resolved)
      Entry.new(
        name: tool.model_facing_name, description: clean(tool.description, ONE_LINE),
        state: (writes && STATE_READS_ONLY) || (ready ? STATE_READY : STATE_NOT_GRANTED),
        tool: (Connection.new(agent_run, tool) if ready),
        group: Groups.of_connection(tool.integration), source: tool.integration.provider, handle: tool.name
      )
    end
  end

  # One entry per capability some connection in the workspace can answer. It is ready when the principal may call at
  # least one tool it would run as, and the gateway still decides each call.
  def self.capability_entries(agent_run, tools: Integration::Tool.in_workspace(agent_run.workspace).to_a, resolved: nil)
    principal = agent_run.acting_principal
    resolved ||= principal && granted(agent_run)

    offered = Integrations::Capabilities.offered(agent_run.workspace, tools: tools).map do |spec, able|
      [ spec, able, principal ? able.select { |tool| tool.callable_by?(principal, resolved) } : [] ]
    end
    entries = offered.map do |spec, able, callable|
      writes = agent_run.reads_only? && spec.writes
      ready = !writes && callable.any?
      Entry.new(
        name: spec.tool_name, description: clean(spec.description, ONE_LINE),
        state: (writes && STATE_READS_ONLY) || (ready ? STATE_READY : STATE_NOT_GRANTED),
        tool: (Capability.new(agent_run, spec, able, callable: callable) if ready),
        group: Groups::RESOURCES, source: Chat::Skill::SOURCE_FIREFIGHT, handle: spec.tool_name
      )
    end
    entries + key_query_entries(agent_run, offered) + log_pattern_entries(agent_run, offered)
  end

  # new_log_patterns, offered beside search_logs, which it reads through.
  def self.log_pattern_entries(agent_run, offered)
    logs = offered.find { |spec, _able, _callable| spec.key == Integrations::Capabilities::LOGS }
    return [] unless logs

    ready = logs.last.any?
    [ Entry.new(
      name: LogPatterns::NAME, description: clean(ResourceMap::LogTemplate::DESCRIPTION, ONE_LINE), state: ready ? STATE_READY : STATE_NOT_GRANTED,
      tool: (LogPatterns.new(agent_run, logs) if ready), group: Groups::RESOURCES, source: Chat::Skill::SOURCE_FIREFIGHT, handle: LogPatterns::NAME
    ) ]
  end

  # run_key_query, offered once some capability a key check reads through is offered, and ready when the agent may
  # run one of them. Each check is still routed and authorized as its capability.
  def self.key_query_entries(agent_run, offered)
    reads = offered.select { |spec, _able, _callable| ResourceMap::KeyQueries::CAPABILITIES_READ.include?(spec.key) }
    return [] if reads.empty?

    ready = reads.any? { |_spec, _able, callable| callable.any? }
    [ Entry.new(
      name: KeyQuery::NAME, description: clean(ResourceMap::KeyQueries::DESCRIPTION, ONE_LINE), state: ready ? STATE_READY : STATE_NOT_GRANTED,
      tool: (KeyQuery.new(agent_run, reads) if ready), group: Groups::RESOURCES, source: Chat::Skill::SOURCE_FIREFIGHT, handle: KeyQuery::NAME
    ) ]
  end

  def self.granted(agent_run)
    Ability::Resolver.resolve(agent_run.acting_principal, agent_run.workspace)
  end
end
