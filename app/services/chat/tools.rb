# Everything the agent could reach. The acting principal's permissions decide which entries are callable.
module Chat::Tools
  STATE_READY = :ready
  STATE_NOT_GRANTED = :not_granted
  STATE_NOT_CONNECTED = :not_connected

  Entry = Data.define(:name, :description, :state, :tool) do
    # Each asked word counts once with its synonyms, so a tool covering more of the question wins, and the name weighs most.
    def score(query)
      asked = concepts(query)
      return 0 if asked.empty?

      in_name = terms(name)
      anywhere = in_name + terms(description)
      (asked.count { |concept| concept.intersect?(anywhere) } * 10) + (asked.count { |concept| concept.intersect?(in_name) } * 5)
    end

    def terms(text) = words(text).map(&:singularize).to_set

    private

    def concepts(query)
      words(query).reject { |word| STOP_WORDS.include?(word) }.map(&:singularize).uniq
        .map { |word| Set[word, *SYNONYMS.fetch(word, [])] }
    end

    def words(text) = text.to_s.downcase.scan(/[a-z0-9]+/)
  end

  # Words that say nothing about which tool is wanted.
  STOP_WORDS = %w[a an the to of for in on at and or is are be can could you i me my our we this that it with].to_set.freeze

  # How people ask for an action, mapped to the words the tools use for it.
  SYNONYMS = {
    "create" => %w[declare open new start raise add], "open" => %w[declare create new start],
    "start" => %w[declare open create begin], "raise" => %w[declare escalate], "lead" => %w[role assign],
    "owner" => %w[role assign], "commander" => %w[role assign], "close" => %w[resolve cancel], "end" => %w[resolve],
    "add" => %w[invite create upsert], "invite" => %w[add pull], "page" => %w[escalate],
    "grant" => %w[give ability permission], "give" => %w[grant assign], "permission" => %w[ability grant],
    "delete" => %w[remove revoke], "remove" => %w[delete revoke], "update" => %w[post upsert change edit],
    "edit" => %w[update upsert change], "note" => %w[update post]
  }.freeze

  # What a reader sees while the agent works. conclude and record_hypothesis are how it writes,
  # not what it looked at, so they are never shown.
  INTERNAL = %w[conclude record_hypothesis find_tools].freeze

  HEADLINE_ARGUMENTS = %w[query name identifier title].freeze
  ASKED_LIMIT = 60

  KIND_READ = "read"
  KIND_ACT = "act"

  Step = Data.define(:title, :headline, :asked)

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

  # nil for the agent's own bookkeeping, which is never shown.
  def self.step(tool_name, arguments)
    return nil if tool_name.blank? || INTERNAL.include?(tool_name.to_s)

    asked = arguments.to_h.filter_map { |name, value| [ name.to_s, value.to_s.truncate(ASKED_LIMIT) ] if value.present? }
    headline = HEADLINE_ARGUMENTS.filter_map { |wanted| asked.assoc(wanted)&.last }.first.to_s
    Step.new(title: tool_name.to_s.tr("_", " ").humanize, headline: headline, asked: asked)
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
  def self.hand_over(agent_run, tool_name, text)
    chat = agent_run.chat
    return FirefightAi::Evidence.frame(tool_name, text) if chat.nil? || text.to_s.length <= chat.result_limit

    saved = chat.saved_results.keep!(tool_name: tool_name, text: text)
    preview = FirefightAi::Evidence.preview(text, handle: saved.handle, read_with: ReadResult.tool_name)
    FirefightAi::Evidence.frame(tool_name, preview)
  end

  def self.catalog(agent_run)
    firefight_entries(agent_run) + connection_entries(agent_run) + unconnected_entries(agent_run)
  end

  def self.firefight_entries(agent_run)
    principal = agent_run.acting_principal
    workspace = agent_run.workspace
    keys = Mcp::Tools.all.to_h { |tool_class| [ tool_class, Ability::Action.system_key(*tool_class.authorization(workspace, {})) ] }
    actions = Ability::Action.system_actions.where(key: keys.values).index_by(&:key)

    keys.map do |tool_class, action_key|
      ready = principal.present? && principal.permitted_to?(actions[action_key], workspace)
      Entry.new(
        name: tool_class.name_value, description: tool_class.description_value.to_s,
        state: ready ? STATE_READY : STATE_NOT_GRANTED,
        tool: (Firefight.new(agent_run, tool_class, actions[action_key]) if ready)
      )
    end
  end

  def self.connection_entries(agent_run)
    principal = agent_run.acting_principal
    resolved = principal && granted(agent_run)

    Integration::Tool.in_workspace(agent_run.workspace).map do |tool|
      ready = principal.present? && tool.callable_by?(principal, resolved)
      Entry.new(
        name: tool.model_facing_name, description: tool.description.to_s,
        state: ready ? STATE_READY : STATE_NOT_GRANTED,
        tool: (Connection.new(agent_run, tool) if ready)
      )
    end
  end

  # Named so the agent can say a provider is not wired up rather than that it found nothing.
  def self.unconnected_entries(agent_run)
    connected = agent_run.workspace.integrations.active.pluck(:provider)

    IntegrationProvider.all.reject { |provider| connected.include?(provider.key) }.map do |provider|
      Entry.new(name: provider.name, description: provider.description, state: STATE_NOT_CONNECTED, tool: nil)
    end
  end

  def self.granted(agent_run)
    Ability::Resolver.resolve(agent_run.acting_principal, agent_run.workspace)
  end
end
