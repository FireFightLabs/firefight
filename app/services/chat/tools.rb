# Everything the agent could reach. The acting principal's permissions decide which entries are callable.
module Chat::Tools
  STATE_READY = :ready
  STATE_NOT_GRANTED = :not_granted
  STATE_NOT_CONNECTED = :not_connected
  STATE_SWITCHED_OFF = :switched_off

  # One line is what the agent reads about a tool before it opens it. Another system's words about
  # itself are cut to that and stripped of anything that is not text.
  ONE_LINE = 200
  TITLE_LIMIT = 60
  FULL_DESCRIPTION = 2_000

  Entry = Data.define(:name, :description, :state, :tool, :group)

  def self.clean(text, limit)
    text.to_s.gsub(/[[:cntrl:]]/, " ").squish.truncate(limit)
  end

  HEADLINE_ARGUMENTS = %w[query name identifier title].freeze
  ASKED_LIMIT = 60

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
    reading = name == ReadResult.tool_name || firefight_reading_names.include?(name) || workspace.reading_tool_names.include?(name)
    reading ? KIND_READ : KIND_ACT
  end

  def self.firefight_reading_names
    @firefight_reading_names ||= Mcp::Tools.all.filter_map { |tool_class| tool_class.name_value.to_s if tool_class.annotations_value&.read_only_hint }.to_set
  end

  Confirmation = Data.define(:tool_call_id, :question, :asked, :status)
  CONFIRMATION_STATUSES = {
    Chat::APPROVAL_REQUESTED => :awaiting, Chat::APPROVAL_APPROVED => :confirmed, Chat::APPROVAL_DENIED => :cancelled
  }.freeze

  # How the agent writes and finds its way, not what it looked at, so a reader is never shown them.
  def self.internal_names
    @internal_names ||= [
      Open.tool_name, Investigation::Tools::Conclude.tool_name, Investigation::Tools::RecordHypothesis.tool_name
    ].freeze
  end

  # nil for the agent's own bookkeeping, which is never shown.
  def self.step(tool_name, arguments)
    return nil if tool_name.blank? || internal_names.include?(tool_name.to_s)

    asked = shown_arguments(arguments)
    Step.new(
      title: tool_name.to_s.tr("_", " ").humanize, headline: headline_for(tool_name, asked), asked: asked,
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

  def self.confirmation(tool_call)
    step = step(tool_call.name, tool_call.arguments)
    Confirmation.new(
      tool_call_id: tool_call.tool_call_id, question: "#{step&.title || tool_call.name.humanize}?",
      asked: step&.asked || [], status: CONFIRMATION_STATUSES.fetch(tool_call.approval, :awaiting)
    )
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
  def self.mark_failed(agent_run, tool_call_id)
    return if tool_call_id.blank?

    Chat.find_by(owner: agent_run.chat_owner)&.mark_failed!(tool_call_id)
  end

  # What a step is called wherever it is cited later, such as "Get form declare".
  def self.label(tool_name, arguments)
    shown = step(tool_name, arguments)
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

  def self.catalog(agent_run)
    firefight_entries(agent_run) + connection_entries(agent_run)
  end

  def self.firefight_entries(agent_run)
    principal = agent_run.acting_principal
    workspace = agent_run.workspace
    offered = Mcp::Tools.all.reject { |tool_class| Groups::NOT_FOR_HALON.include?(tool_class.name_value.to_s) }
    keys = offered.to_h { |tool_class| [ tool_class, Ability::Action.system_key(*tool_class.authorization(workspace, {})) ] }
    actions = Ability::Action.system_actions.where(key: keys.values).index_by(&:key)

    keys.map do |tool_class, action_key|
      ready = principal.present? && principal.permitted_to?(actions[action_key], workspace)
      Entry.new(
        name: tool_class.name_value, description: clean(tool_class.description_value, ONE_LINE),
        state: ready ? STATE_READY : STATE_NOT_GRANTED,
        tool: (Firefight.new(agent_run, tool_class, actions[action_key]) if ready),
        group: Groups.of_firefight_tool(tool_class.name_value)
      )
    end
  end

  def self.connection_entries(agent_run)
    principal = agent_run.acting_principal
    resolved = principal && granted(agent_run)

    Integration::Tool.in_workspace(agent_run.workspace).map do |tool|
      ready = principal.present? && tool.callable_by?(principal, resolved)
      Entry.new(
        name: tool.model_facing_name, description: clean(tool.description, ONE_LINE),
        state: ready ? STATE_READY : STATE_NOT_GRANTED,
        tool: (Connection.new(agent_run, tool) if ready),
        group: Groups.of_connection(tool.integration)
      )
    end
  end

  def self.granted(agent_run)
    Ability::Resolver.resolve(agent_run.acting_principal, agent_run.workspace)
  end
end
