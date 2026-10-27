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

  # source is the provider a call went through, such as GitHub, which a run of steps is summed up by. nil for Firefight's
  # own tools.
  # line is the step as a chat platform's thread shows it, plain words that never name the tool, its connection or a
  # file. nil when the title already reads that way.
  Step = Data.define(:title, :headline, :asked, :card, :source, :line) do
    def initialize(source: nil, line: nil, **) = super

    def shown_line = line || title
  end

  # A result the page draws as something other than text. The step carries only what to draw, and the page
  # reads the rows from the workspace as they are now, so a card says the truth after the person acts on it.
  Card = Data.define(:kind, :category) do
    # Most cards draw what a step returned, so they wait for it. Helpers are drawn while they work.
    def shown_while_running? = kind == CARD_HELPERS
  end
  CARD_INTEGRATIONS = "integrations".freeze
  # The run a chat started. The page finds it by the step's tool call, since the run exists only once the tool has run.
  CARD_INVESTIGATION = "investigation".freeze
  # Charts a tool returned. The page finds them by the step's tool call, since a tool only returns them when it has data.
  CARD_CHART = "chart".freeze
  # Helpers a run_helpers call started, drawn under its step while they work and after. The page finds them by the
  # step's tool call, and draws them from the chat's helpers as they are now.
  CARD_HELPERS = "helpers".freeze
  # The pages Halon's browser saw. The page finds them by the step's tool call, since they exist once the check ran.
  CARD_SCREENSHOTS = "screenshots".freeze
  # Halon's theory board, drawn under the last step that updated it. The page finds it by the step's tool call.
  CARD_THEORIES = "theories".freeze
  CARD_KINDS = [ CARD_INTEGRATIONS, CARD_INVESTIGATION, CARD_CHART, CARD_HELPERS, CARD_SCREENSHOTS, CARD_THEORIES ].freeze

  def self.chart_card = Card.new(kind: CARD_CHART, category: nil)

  def self.card_for(tool_name, arguments)
    return Card.new(kind: CARD_INVESTIGATION, category: nil) if tool_name.to_s == FirefightTools::START_INVESTIGATION
    return Card.new(kind: CARD_SCREENSHOTS, category: nil) if tool_name.to_s == Browser::NAME
    return nil unless tool_name.to_s == FirefightTools::LIST_INTEGRATIONS

    category = arguments.to_h.stringify_keys["category"]
    return nil if category.blank?

    Card.new(kind: CARD_INTEGRATIONS, category: IntegrationProvider.category_for!(category).slug)
  rescue ArgumentError
    nil
  end

  # A tool that only reads is the agent looking something up, which the page shows as thinking rather than as a change.
  # So is a call its guard shows to read through a tool that can also change things, when the call's arguments are known.
  def self.kind(tool_name, workspace, arguments = nil)
    name = tool_name.to_s
    reading = [ ReadResult.tool_name, Helpers::NAME, AskSpecialist::NAME, Theories::NAME, Web::SEARCH, Web::READ, Docs::SEARCH, Docs::READ, OutsideCheck::NAME, WhatChanged::NAME ].include?(name) ||
              (name == Browser::NAME && !Browser.sends?(arguments)) ||
              firefight_reading_names.include?(name) || workspace.reading_tool_names.include?(name) || guarded_read?(workspace, name, arguments)
    reading ? KIND_READ : KIND_ACT
  end

  def self.guarded_read?(workspace, name, arguments)
    tool = arguments && Target.label(workspace, name)
    tool.present? && Integrations::ReadGuards.reads?(tool, arguments)
  end

  def self.firefight_reading_names
    @firefight_reading_names ||= FirefightTools.all.filter_map { |tool_class| tool_class.name_value.to_s if tool_class.annotations_value&.read_only_hint }.to_set
  end

  # A tool that changes permissions, a credential, an approval or a webhook is asked about every time, so Allow for the
  # rest of this chat never covers it. So is a connection's tool that changes who can reach something or sets a secret
  # (Integrations::SafeChanges.access?), found by its name in the workspace.
  def self.asks_a_person?(tool_name, workspace = nil)
    return true if person_confirmed_names.include?(tool_name.to_s)

    tool = workspace && Target.label(workspace, tool_name)
    tool.present? && Integrations::SafeChanges.access?(tool)
  end

  def self.person_confirmed_names
    @person_confirmed_names ||= FirefightTools.all.filter_map { |tool_class| tool_class.name_value.to_s if tool_class.asks_a_person? }.to_set
  end

  # target is what the call reaches, worked out from the tool when it was asked (Chat::Tools::Target), and call what the
  # tool does, such as "Api request". Both are nil for Firefight's own tools and for calls asked before targets were kept.
  # short_title is the agent's few words naming the change, such as "Pause dev-web", nil on calls asked before it was.
  # read is what was read from outside before the call was asked (Chat::Tools::Provenance), nil when nothing was.
  # safeguards are rows saying what the call will touch beyond its arguments (Chat::Safeguards): the rows a statement
  # changes, who started what it stops. expires lists the times a change customers feel may be undone after, in time
  # order, and is empty for any other call, with chosen_expiry the one chosen so far and undo_words what undoing it means
  # when its provider says. for_chat is false for a statement that writes rows, which is asked about on its own each
  # time. waiting_on names the owner a confirmed call waits for. A call may be allowed for the rest of the chat only when
  # nothing was read from outside and for_chat holds. support is the reads from the call's turn that Halon named as
  # showing the change will help (Chat::Tools::LookFirst). page is the screenshot of the page a browser send would go
  # from, taken when the check stopped before it, and its would_send_rows say what it sends. plan_undo is how the plan
  # step the call carries out says to put it back. effect is what the call changes in plain words, worked out from its
  # action rather than Halon's words (Chat::Tools.effect), nil when nothing more than "a change" is known. decided_by is
  # the member who answered it, outcome how it went once it ran (Chat::StepOutcome), and progress how far a code change
  # got while it runs (Chat::CodeFixProgress).
  # listed is whether an entry of what Halon may do without asking covers the call, which still asks since outside text
  # holds its values.
  Confirmation = Data.define(:tool_call_id, :question, :intent, :asked, :status, :target, :call, :read, :safeguards, :expires, :for_chat, :waiting_on,
                             :support, :page, :short_title, :chosen_expiry, :undo_words, :plan_undo, :tool_name, :effect, :decided_by, :outcome, :progress,
                             :listed) do
    def initialize(read: nil, safeguards: [], expires: [], for_chat: true, waiting_on: nil, support: [], page: nil, short_title: nil,
                   chosen_expiry: nil, undo_words: nil, plan_undo: nil, tool_name: nil, effect: nil, decided_by: nil, outcome: nil, progress: nil,
                   listed: false, **) = super

    # The question as a label, which names the tool when the agent's words lead.
    def tool_label = question.delete_suffix("?")

    # What will happen, in plain words: the agent's few words, else its sentence, else the call by its tool's name.
    def title = short_title || intent&.delete_suffix(".") || (target ? call : tool_label)

    # Where it happens, quieter under the title: what the call reaches, or the tool when the agent's words lead.
    def label
      shown = target || tool_label
      shown unless shown == title
    end

    # What it does and how to put it back when that is known, under the title.
    def summary
      said = (Chat::Tools.sentence(intent) if short_title && intent)
      put_back = (Chat::Tools.sentence("#{PUT_BACK} #{plan_undo}") if plan_undo)
      [ said, put_back ].compact.join(" ").presence
    end

    # What Halon asks to do, as the end of "Halon wants to: ...", such as "pause dev-web".
    def action = Chat::Tools.lowercase_lead(Chat::Tools.plain(title, ACTION_LIMIT))

    # The request itself, the title of the card in every place it is asked.
    def heading = "#{WANTS_TO} #{action}"

    # The one line under the heading. What the call changes when its action says something worth stopping for, else why
    # Halon asks when it said more than the title, else what it changes as far as its action says. Free of code and ids,
    # so it reads plainly. The rest is under Details.
    def line = effect || reason || plain_change

    # Halon's own sentence, when it says more than the title does.
    def reason
      return unless short_title && intent

      Chat::Tools.sentence(Chat::Tools.plain(intent, LINE_LIMIT))
    end

    def plain_change = (Chat::Tools.changes_in(Chat::Tools.place_of(target)) if target)

    # Said with the line when outside text holding the change's own values was read before asking, so the person checks
    # the request is theirs. Where it came from in a word, the full list under Details.
    def caution
      places = holding_sources.map { |source| Chat::Tools::Provenance.place(source.from) }.uniq
      [ (format(CAUTION, places: places.to_sentence) if places.any?), (LISTED_BUT_READ if listed) ].compact.join(" ").presence
    end

    def holding_sources = read&.sources&.select { |source| source.found.any? } || []

    # What the undo choice is labelled, present only when the call offers one.
    def undo_label = ((undo_words || UNDO_AUTOMATICALLY) if expires.any?)

    def allowable? = read.nil? && for_chat

    # One sentence naming where outside text holding the change's own values came from, in the words both the dashboard
    # and Slack show. Absent when what was read holds none of them, so the warning appears only when it means something.
    def read_lead
      holding = holding_sources
      return if holding.empty?

      "Halon read #{holding.map { |source| source.from || OUTSIDE_TEXT }.uniq.to_sentence} before asking. Check the reason above is yours."
    end

    # Heads the list of what was read, saying why Allow for the rest of this chat is not offered.
    def read_heading = (READ_HEADING if read)

    # Each read as a label and what it shows: the change's own values it mentions, or that it was read earlier.
    def read_rows
      return [] unless read

      rows = read.sources.map { |source| [ source.label, source.found.any? ? "Mentions #{source.found.join(', ')}" : READ_EARLIER ] }
      read.others.positive? ? rows + [ [ "#{read.others} more #{read.others == 1 ? 'read' : 'reads'}", READ_EARLIER ] ] : rows
    end

    # Heads the reads Halon named, in the words both the dashboard and Slack show.
    def support_lead = (SUPPORT_LEAD if support.any?)

    # Each read Halon named as a point: what it said the read showed with the read as its source, or the read alone.
    def support_points
      support.map { |each| each.said.present? ? SupportPoint.new(text: each.said, source: each.label) : SupportPoint.new(text: each.label, source: nil) }
    end
  end
  SupportPoint = Data.define(:text, :source)
  SUPPORT_LEAD = "Why".freeze
  READ_EARLIER = "Read earlier in this chat".freeze
  READ_HEADING = "Read from outside Firefight before asking. Allow for the rest of this chat does not cover a change asked after that.".freeze
  # Where outside text came from, for a call asked before each read kept it.
  OUTSIDE_TEXT = "text from outside Firefight".freeze
  PUT_BACK = "To put it back:".freeze
  # The button that approves a change. The heading already says what it is.
  APPROVE = "Approve".freeze
  UNDO_AUTOMATICALLY = "Undo automatically".freeze
  # The same choice for a change no fixed call puts back, which Halon is asked to put back in the chat when it is due.
  ASK_HALON_TO_PUT_BACK = "Ask Halon to put it back".freeze
  WANTS_TO = "Halon wants to:".freeze
  CAUTION = "It read text from %<places>s that other people wrote. Check this is what you want.".freeze
  LISTED_BUT_READ = "It is on the list of what Halon may do without asking, and asks anyway, since Halon has read text from outside Firefight in this chat.".freeze
  ACTION_LIMIT = 120
  LINE_LIMIT = 160
  # A commit, a review or a comment named by its id says nothing to the person approving, so the card leaves them out,
  # with the brackets around them. A number short enough to be a pull request's or an issue's stays.
  RAW_ID = /\b(?:(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}|\d{6,})\b/i
  CODE = /`+/

  def self.sentence(text)
    text = text.to_s.strip
    text.match?(/[.!?]\z/) ? text : "#{text}."
  end

  # Words the agent wrote, without code marks or raw ids, on one line and cut short.
  def self.plain(text, limit)
    text.to_s.gsub(CODE, "").gsub(/\s*\([^()]*#{RAW_ID.source}[^()]*\)/i, "").gsub(RAW_ID, "").gsub(/\(\s*\)/, "").squish.gsub(/\s+([,.;:!?)])/, '\1').truncate(limit)
  end

  # "Pause dev-web" reads "pause dev-web" after "Halon wants to:", while a name such as PR, GitHub or iOS keeps its case.
  def self.lowercase_lead(text)
    first = text[/\A\S+/].to_s
    first.match?(/\A[A-Z][a-z]*\z/) ? text.sub(first, first.downcase) : text
  end

  def self.changes_in(place) = "Changes something in #{place}."

  # One time a change customers feel may be undone after. value is what the answer sends back, minutes or keep.
  Expiry = Data.define(:value, :label)

  # A call that waits for the person's decision carries one sentence saying what it will do, and a few words naming the
  # change for its title and the button that approves it, both written by the agent for whoever approves it. They are
  # taken off before the call is made, so the tool never sees them.
  INTENT_ARG = "intent".freeze
  INTENT = {
    "type" => "string",
    "description" => "One sentence for the person asked to approve this call: what it will do and why, in plain words, " \
                     "such as \"List the zones in the account to find the one for firefight.app\""
  }.freeze
  SHORT_TITLE_ARG = "short_title".freeze
  SHORT_TITLE = {
    "type" => "string",
    "description" => "The change in two to five words starting with a verb, for the title of the approval and its button, " \
                     "such as \"Pause dev-web\" or \"Purge the firefight.app cache\""
  }.freeze
  # Every argument the agent writes for the person alone, which no tool is given.
  FOR_PERSON = [ INTENT_ARG, SHORT_TITLE_ARG ].freeze

  def self.with_intent(schema)
    schema = schema.deep_dup
    schema["properties"] = (schema["properties"] || {}).merge(INTENT_ARG => INTENT, SHORT_TITLE_ARG => SHORT_TITLE)
    schema["required"] = (Array(schema["required"]) + FOR_PERSON).uniq
    schema
  end

  # The intent and the short title for a tool that waits only for some of its calls, saying when they are needed.
  def self.for_person_properties(needed)
    { INTENT_ARG => INTENT.merge("description" => "#{INTENT['description']}. #{needed}"),
      SHORT_TITLE_ARG => SHORT_TITLE.merge("description" => "#{SHORT_TITLE['description']}. #{needed}") }
  end

  def self.intent_of(arguments) = arguments.to_h.stringify_keys[INTENT_ARG].to_s.strip.presence

  def self.short_title_of(arguments) = arguments.to_h.stringify_keys[SHORT_TITLE_ARG].to_s.squish.presence

  # Everything the agent wrote for the person about a call, which is what names the account it means to reach.
  def self.words_for_person(arguments) = [ short_title_of(arguments), intent_of(arguments) ].compact.join(". ").presence
  CONFIRMATION_STATUSES = {
    Chat::APPROVAL_REQUESTED => :awaiting, Chat::APPROVAL_APPROVED => :confirmed, Chat::APPROVAL_DENIED => :cancelled,
    Chat::APPROVAL_WITHDRAWN => :withdrawn, Chat::APPROVAL_OWNER_ASKED => :owner_asked
  }.freeze

  # What the workspace knows, its memory and its handbook. A run that only measures Halon reads both and never changes
  # either, so nothing it does reaches the Memory page or the handbook.
  def self.memory(agent_run)
    return [ Recall.new(agent_run), SearchHandbook.new(agent_run) ] unless agent_run.changes_memory?

    [ Remember.new(agent_run), Recall.new(agent_run), DisputeMemory.new(agent_run), SearchHandbook.new(agent_run), ProposeHandbookEdit.new(agent_run) ]
  end

  # How the agent writes and finds its way, not what it looked at, so a reader is never shown them.
  def self.internal_names
    @internal_names ||= [
      Open.tool_name, Investigation::Tools::Conclude.tool_name, Investigation::Tools::RecordHypothesis.tool_name,
      Chat::Specialists::Report::NAME, *Conversation::Tools.plan_tool_names
    ].freeze
  end

  # nil for the agent's own bookkeeping, which is never shown. With a workspace, a connection tool is titled by what it
  # does and the connection it runs through, as the confirmation names it.
  def self.step(tool_name, arguments, workspace: nil)
    return nil if tool_name.blank? || internal_names.include?(tool_name.to_s)
    return Helpers.shown(arguments) if tool_name.to_s == Helpers::NAME
    return AskSpecialist.shown(arguments) if tool_name.to_s == AskSpecialist::NAME
    return Theories.shown(arguments) if tool_name.to_s == Theories::NAME

    asked = shown_arguments(arguments.to_h.stringify_keys.except(*FOR_PERSON, LookFirst::BECAUSE))
    Step.new(
      title: title_for(tool_name, workspace, arguments.to_h.stringify_keys), headline: intent_of(arguments) || headline_for(tool_name, asked), asked: asked,
      card: card_for(tool_name, arguments), source: source_for(tool_name, workspace), line: line_for(tool_name, arguments, workspace)
    )
  end

  # The words the agent wrote for the call when it wrote any, otherwise the kind of system the call reads, as an
  # investigation's checklist names it (Investigation::Progress::TITLES), so "Read the code" and never "Github fix code · acme".
  # A connection whose provider answers no kind of question is named by its provider, and Firefight's own tools that read
  # no system of the workspace's say they gathered what Firefight knows.
  def self.line_for(tool_name, arguments, workspace)
    short_title_of(arguments) || line_by_group(tool_name.to_s, workspace)
  end

  def self.line_by_group(name, workspace)
    titles = Investigation::Progress::TITLES
    group = Investigation::Progress.tool_groups[name]
    return titles.fetch(group) if group

    integration = workspace && Target.label(workspace, name)&.integration
    if integration
      group = Investigation::Progress::SPECIALIST_GROUPS[IntegrationProvider.specialist_for(integration.provider)]
      return group ? titles.fetch(group) : "Checked #{source_for(name, workspace)}"
    end

    titles.fetch(Investigation::Progress::RESOURCE_GROUPS[own_resource(name, workspace)] || Investigation::Progress::KNOWN)
  end

  def self.own_resource(name, workspace)
    own = FirefightTools.all.find { |tool_class| tool_class.name_value.to_s == name }
    own && Array(own.authorization(workspace, {})).first
  rescue NotImplementedError, ActiveRecord::RecordNotFound
    nil
  end

  def self.source_for(tool_name, workspace)
    integration = workspace && Target.label(workspace, tool_name)&.integration
    integration && (IntegrationProvider.find(integration.provider)&.name || integration.name)
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
    @required_arguments ||= FirefightTools.all.to_h do |tool_class|
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

  # How every answer to a call held for an approval starts, so a caller that only has the words can tell it waits.
  WAITING = "Needs an approval and was not run".freeze

  # held is whether the person is asked to run it once approved, which only a chat does.
  def self.waiting_for_approval(action_key, held: false)
    return "#{WAITING}: #{action_key}. Carry on with what you can reach and say what you could not check." unless held

    "#{WAITING}: #{action_key}. Whoever can approve it has been asked. Once someone approves it, the " \
      "person is asked in this chat whether to run it, so never call it again yourself. Tell them it is waiting for approval, " \
      "and carry on with what you can reach."
  end

  # A call leads with what it will do in the agent's words, with what it reaches worked out from the tool right under
  # them, since the agent's words can name another account than the one the tool reaches.
  def self.confirmation(tool_call)
    step = step(tool_call.name, tool_call.arguments)
    target = tool_call.try(:target).presence
    call = (call_title(tool_call) if target)
    chat = tool_call.try(:message)&.chat
    repair = Chat::DataRepair.for_call(chat, tool_call.tool_call_id)
    owner = Chat::OwnerAsk.for_call(chat, tool_call.tool_call_id)
    workspace = chat&.workspace
    mitigation = Chat::Mitigation.for_call(chat, tool_call.tool_call_id)
    page = browser_page(chat, tool_call)
    Confirmation.new(
      tool_call_id: tool_call.tool_call_id, question: browser_question(tool_call) || (target ? "#{call} on #{target}?" : "#{step&.title || tool_call.name.humanize}?"),
      intent: intent_of(tool_call.arguments), asked: (step&.asked || []) + planned(tool_call), status: CONFIRMATION_STATUSES.fetch(tool_call.approval, :awaiting),
      target: target, call: call, read: Provenance.stored(tool_call),
      safeguards: [ *repair&.confirmation_rows, owner&.confirmation_row, *page&.would_send_rows ].compact,
      expires: expiries(mitigation), for_chat: repair.nil? && !Browser.sends?(tool_call.arguments) && !asks_a_person?(tool_call.name, workspace),
      waiting_on: (owner.owner_name if tool_call.approval == Chat::APPROVAL_OWNER_ASKED && owner),
      support: workspace ? LookFirst.support(chat, tool_call, workspace) : [], page: page,
      short_title: short_title_of(tool_call.arguments), chosen_expiry: chosen_expiry(mitigation), undo_words: undo_words(workspace, mitigation, tool_call.arguments),
      plan_undo: plan_undo(chat, tool_call), tool_name: tool_call.name.to_s, effect: effect(workspace, tool_call.name, target),
      decided_by: decided_by(tool_call), listed: tool_call.try(:allowance_id).present? && tool_call.try(:unasked_reason).blank?, **ran(chat, tool_call)
    )
  end

  # How an approved call went, and how far a code change got, once it was approved. Nothing for a call still asked.
  def self.ran(chat, tool_call)
    return {} unless tool_call.approval == Chat::APPROVAL_APPROVED

    { outcome: Chat::StepOutcome.for_call(tool_call, chat), progress: chat && chat.step_progresses.of_call(tool_call.tool_call_id, since: tool_call.created_at).last&.work }
  end

  def self.decided_by(tool_call)
    id = tool_call.try(:decided_by_id)
    id && WorkspaceMembership.find_by(id: id)
  end

  # What a call through a connection's tool changes that is worth stopping for, in plain words, from what its action
  # declares rather than from Halon's words: what it does beyond a plain change (Ability::Action::EFFECTS). A tool's
  # action is never known to be reversible, so that is not claimed either way. nil for a plain change, and for a call
  # that is not a connection's tool.
  def self.effect(workspace, tool_name, target)
    tool = workspace && Target.label(workspace, tool_name)
    action = tool && Ability::Action.lookup("#{tool.integration.slug}.#{tool.name}", workspace)
    return unless action

    place = target ? place_of(target) : tool.integration.display_name
    declared = EFFECT_LINES.keys.find { |effect| action.effect?(effect) }
    format(EFFECT_LINES.fetch(declared), place: place) if declared
  end

  # The connection a target names, without the account or project it reaches, such as "GitHub".
  def self.place_of(target) = target.split(",").first.strip
  EFFECT_LINES = {
    Ability::Action::EFFECT_STOPS => "Stops or removes something in %<place>s.",
    Ability::Action::EFFECT_MITIGATION => "Changes what customers get from %<place>s until it is undone.",
    Ability::Action::EFFECT_DATA_WRITE => "Changes rows in %<place>s."
  }.freeze

  # What undoing a change customers feel means, such as starting a paused service again, when Firefight puts it back
  # itself, and ASK_HALON_TO_PUT_BACK when no fixed call does and Halon is asked in the chat instead.
  # given is the call as Halon made it, which names a plan by the capability's own argument.
  def self.undo_words(workspace, mitigation, given = {})
    return unless workspace && mitigation&.proposed?

    if mitigation.tool_name == Integrations::Capabilities.spec(Integrations::Capabilities::SCALE).tool_name
      return given.to_h.stringify_keys[Integrations::Capabilities::PLAN_ARG].blank? ? Integrations::Mitigations::SCALES_BACK : ASK_HALON_TO_PUT_BACK
    end

    made_with = Integration::Tool.by_action_key(workspace, mitigation.action_key)
    put_back = made_with && (Integrations::SafeChanges.declares_undo?(made_with) || Integrations::Mitigations.undo_arguments(made_with, mitigation.arguments))
    return ASK_HALON_TO_PUT_BACK unless mitigation.undo_steps.any? || put_back

    Integrations::Mitigations.undo_words(made_with, mitigation.arguments) if made_with
  end

  # How the plan step this call carries out says to put it back, while that step is running. A step of a plan's own undo
  # is putting something back already.
  def self.plan_undo(chat, tool_call)
    step = chat && Chat::Plan::Step.running_change(chat)
    step.undo.presence if step && step.tool.to_s == tool_call.name.to_s && !step.plan.undo?
  end

  # The page a browser send goes from, as the check that stopped before it saw it, or nil for any other call.
  def self.browser_page(chat, tool_call)
    return unless tool_call.name.to_s == Browser::NAME && Browser.sends?(tool_call.arguments)

    check = Chat::BrowserCheck.from(tool_call.arguments.to_h.except(*FOR_PERSON, LookFirst::BECAUSE))
    Chat::Screenshot.stopped_before(chat, check.digest, check.send_step, fresh: false, viewport: check.viewports.first)
  rescue Chat::BrowserCheck::Refused
    nil
  end

  # A send is asked about as what it does, on the site it goes to, rather than as a check.
  def self.browser_question(tool_call)
    return unless tool_call.name.to_s == Browser::NAME && Browser.sends?(tool_call.arguments)

    host = URI.parse(tool_call.arguments.to_h.stringify_keys[Browser::URL_ARG].to_s).host
    "Let Halon's browser send step #{tool_call.arguments.to_h.stringify_keys[Browser::SEND_STEP_ARG]} on #{host || 'the page'}?"
  rescue URI::InvalidURIError
    nil
  end

  # The times a change customers feel may be undone after, in time order from never. Empty for a call that is not one.
  def self.expiries(mitigation)
    return [] unless mitigation&.proposed?

    [ Expiry.new(value: Chat::Mitigation::KEEP, label: NEVER),
      *Chat::Mitigation::DURATIONS.map { |minutes| Expiry.new(value: minutes.to_s, label: Chat::Mitigation.duration_short(minutes)) } ]
  end
  NEVER = "Never".freeze

  # The time chosen so far, which the choice starts on: the default until someone picks another, and keep when nil.
  def self.chosen_expiry(mitigation)
    return unless mitigation&.proposed?

    mitigation.duration_minutes&.to_s || Chat::Mitigation::KEEP
  end

  # What the tool does, by its own name rather than the connection's, such as "Api request".
  # A connection tool reads as "Api request · Production (Hosting)", never as its connection's slug made into words, which
  # reads like the provider's name. Anything else is its own name made into words.
  # A call that names one project or workspace of a connection that reaches several reads with it, as "Api request ·
  # Production (Hosting), project acme".
  def self.title_for(tool_name, workspace, arguments = {})
    tool = workspace && Target.label(workspace, tool_name)
    return tool_name.to_s.tr("_", " ").humanize unless tool

    key = IntegrationProvider.find(tool.integration.provider)&.scope_field&.key
    scope = key && arguments[key].presence
    connection = scope.is_a?(String) ? workspace.labelled_connection(tool.integration.id).target_label(scope: scope) : tool.integration.display_name
    "#{tool.name.tr('_.', '  ').humanize} · #{connection}"
  end

  # A runbook's run, and a workflow made or run, are confirmed as the steps they will take, read from what they are
  # rather than from Halon's words.
  PLANNED = {
    Conversation::Tools::RunRunbook::NAME => Conversation::Tools::RunRunbook, Conversation::Tools::CreateWorkflow::NAME => Conversation::Tools::CreateWorkflow,
    Conversation::Tools::RunWorkflow::NAME => Conversation::Tools::RunWorkflow
  }.freeze

  # Settles what each planned call left to the asker, such as the time zone of a time given without one, into the call
  # when it is asked, so every card shows and the call makes the same thing whoever reads it and whenever it runs.
  def self.settle_asked!(agent_run, tool_calls)
    tool_calls.each do |tool_call|
      tool = PLANNED[tool_call.name.to_s]
      next unless tool.respond_to?(:settled_arguments)

      settled = tool.settled_arguments(agent_run, tool_call.arguments.to_h.deep_stringify_keys)
      tool_call.update_columns(arguments: settled) if settled != tool_call.arguments
    end
  end

  def self.planned(tool_call)
    tool = PLANNED[tool_call.name.to_s]
    workspace = tool && tool_call.message&.chat&.workspace
    workspace ? tool.plan_rows(workspace, tool_call.arguments) : []
  end

  def self.call_title(tool_call)
    workspace = tool_call.message&.chat&.workspace
    tool = workspace && Target.label(workspace, tool_call.name)
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

  # The markers of the charts a call's helpers or specialists drew since it started, said outside their reports so Halon
  # can place them (Chat::Chart::Marker). A call id is unique only within its message, so an earlier call's charts under
  # the same id are left out. nil when they drew none.
  def self.charts_drawn(agent_run, tool_call_id, since:)
    chat = agent_run.chat
    Chat::Chart::Marker.note(chat.charts.where(tool_call_id: tool_call_id, created_at: since..).to_a) if chat && tool_call_id.present?
  end

  # A chat or run working on an incident tells its channel what it learned or disputed. Elsewhere the Memory page shows it.
  def self.tell_incident(agent_run, memory, kind)
    return unless agent_run.changes_memory? && agent_run.incident&.channel_id.present?

    MemoryNoteJob.perform_later(memory.id, kind, agent_run.chat_owner)
  end

  # A memory something contradicted is told to its incident's channel like any dispute. Nobody is asked about it there.
  # The nightly check settles it against production, and only one it cannot settle waits on a person on the Memory page.
  def self.raise_dispute(agent_run, memory)
    tell_incident(agent_run, memory, Chat::MemoryPost::KIND_DISPUTED)
  end

  # A memory write as whoever the agent acts for. A refusal is text the model reads, and the call is marked.
  # The ledger gets ids and flags only, never the fact, since a fact holding a secret is refused only after.
  def self.memory_change(agent_run, crud_action, tool_name:, params:, tool_call_id:, &)
    agent_run.memory_change(crud_action, params: params, tool_name: tool_name, &)
  rescue AbilityGateway::Denied => denied
    mark_failed(agent_run, tool_call_id)
    agent_run.refusal(denied.action_key)
  end

  # kind says whether the provider answered that what was asked about is not there (Chat::StepOutcome).
  # A runbook's run hears of it too, since its steps run with no call of their own to mark (Conversation::Tools::RunRunbook).
  # Read fresh, since a run's chat may have been opened after the run was loaded.
  def self.mark_failed(agent_run, tool_call_id, kind: Chat::StepOutcome::FAILURE_ERROR)
    agent_run.call_failed!(kind) if agent_run.respond_to?(:call_failed!)
    return if tool_call_id.blank?

    Chat.find_by(owner: agent_run.chat_owner)&.mark_failed!(tool_call_id, kind: kind)
  end

  # What a step is called wherever it is cited later, such as "Get form declare".
  def self.label(tool_name, arguments, workspace: nil)
    shown = step(tool_name, arguments, workspace: workspace)
    [ shown&.title, shown&.headline ].compact_blank.join(" ")
  end

  # What the chat found earlier, for whoever acts now, so a grant taken away since is not handed back. In a chat that asks
  # specialists a read a specialist holds is handed back only while Halon may load it (Chat::Specialists.loadable), such
  # as one backing a change Halon still holds.
  def self.known(agent_run, chat)
    names = chat.known_tool_names
    return [] if names.empty?

    ready = catalog(agent_run).select(&:tool)
    if Chat::Specialists.for?(agent_run)
      loadable = Chat::Specialists.loadable(chat, agent_run.workspace, held: names)
      ready = ready.reject { |entry| Chat::Specialists.held_back?(agent_run.workspace, entry, loadable) }
    end
    ready = ready.index_by(&:name)
    names.filter_map { |name| ready[name]&.tool }
  end

  # What may be in Halon's hands. Where the chat asks specialists, a connection's reads are theirs (Chat::Specialists).
  def self.halons(agent_run, entries)
    return entries unless Chat::Specialists.for?(agent_run)

    entries.reject { |entry| Chat::Specialists.reserved?(agent_run.workspace, entry) }
  end

  # How the catalog reaches a chat. Only what whoever acts may call is handed over, built from the same catalog as
  # open_tools reads, so a grant, a read guard, an approval rule and the gateway decide each call exactly as they do for a
  # tool found any other way.
  # Where the provider searches tools itself (FirefightAi.tool_search?), Firefight's own tools and capabilities that only
  # read, and the general reads (what_changed, run_key_query, new_log_patterns), are held from the start. Their writes
  # and every connection tool are handed over deferred, out of the model's context until it searches for one.
  # Anywhere else every tool is held from the start when all of them fit the budget (FirefightAi.fits_up_front?), so
  # the tool list in front of the cached prompt never changes during the chat. Past it nothing is handed over, and the
  # agent opens groups with open_tools.
  # Where the chat asks specialists (specialists true), a connection's reads are theirs and never handed over. Held from
  # the start are Firefight's own tools, the capabilities, the general reads and any connection no specialist reads, and
  # a change in a connected system is loaded by name, by searching or with open_tools, when Halon decides to make it.
  Presented = Data.define(:loaded, :deferred, :searched, :held, :specialists) do
    def initialize(specialists: false, **) = super

    def self.none(specialists: false) = new(loaded: [], deferred: [], searched: false, held: false, specialists: specialists)
  end

  def self.presented(agent_run, choice)
    specialists = Chat::Specialists.for?(agent_run)
    ready = halons(agent_run, catalog(agent_run).select(&:tool))
    core, tail = ready.partition { |entry| entry.source == Chat::Skill::SOURCE_FIREFIGHT && !writing_names.include?(entry.name.to_s) }
    return Presented.new(loaded: core.map(&:tool), deferred: tail.map(&:tool), searched: true, held: false, specialists: specialists) if FirefightAi.tool_search?(choice)
    return held_for_specialists(agent_run, ready, core) if specialists

    tools = ready.map(&:tool)
    FirefightAi.fits_up_front?(tools) ? Presented.new(loaded: tools, deferred: [], searched: false, held: true) : Presented.none
  end

  # Without the provider's tool search a chat that asks specialists holds its own tools and any connection no specialist
  # reads, when they fit, else Firefight's reads, the capabilities that read and the general reads, as a search would. A
  # connection's change is never held, since it is loaded by name when Halon decides to make it.
  def self.held_for_specialists(agent_run, ready, core)
    own = ready.select { |entry| entry.source == Chat::Skill::SOURCE_FIREFIGHT || agent_run.workspace.reading_tool_names.include?(entry.name.to_s) }.map(&:tool)
    return Presented.new(loaded: own, deferred: [], searched: false, held: true, specialists: true) if FirefightAi.fits_up_front?(own)

    tools = core.map(&:tool)
    FirefightAi.fits_up_front?(tools) ? Presented.new(loaded: tools, deferred: [], searched: false, held: false, specialists: true) : Presented.none(specialists: true)
  end

  # Firefight's own tools and capabilities that change something, which a turn finds by searching rather than holding.
  def self.writing_names
    @writing_names ||= (FirefightTools.all.map { |tool_class| tool_class.name_value.to_s } - firefight_reading_names.to_a +
                        Integrations::Capabilities::SPECS.values.select(&:writes).map(&:tool_name)).to_set
  end

  # Offered to the live chat and remembered, so a later turn or a resumed run starts with them.
  def self.offer_to(chat)
    lambda do |tools|
      chat.remember_found_tools!(tools.map(&:name))
      chat.with_tools(*tools)
    end
  end

  # The parts a turn keeps of what it reads, built from the same version (Conversation::Turn#catalog).
  CATALOG_ENTRIES = :entries
  CATALOG_TOOLS = :tools
  CATALOG_SKILLS = :skills

  # A chat's turn reads one for the whole turn (Conversation::Turn#catalog).
  def self.catalog(agent_run)
    return build_catalog(agent_run) unless agent_run.is_a?(Conversation::Turn)

    agent_run.catalog(catalog_version(agent_run), CATALOG_ENTRIES) { build_catalog(agent_run) }
  end

  # The workspace's switched on tools the catalogue is built from: the list the workspace holds (Workspace::ToolCatalogue),
  # which a helper shares with the run it helps, and for a turn getting ready the list its catalogue holds.
  def self.switched_on_tools(agent_run)
    return agent_run.workspace.switched_on_tools unless agent_run.is_a?(Conversation::Turn) && agent_run.catalog_held?

    agent_run.catalog(catalog_version(agent_run), CATALOG_TOOLS) { agent_run.workspace.switched_on_tools }
  end

  # The skills a turn's reminders name, read with its catalogue and again only when it is.
  def self.skills(agent_run)
    return Chat::Skill.available_to(agent_run.workspace) unless agent_run.is_a?(Conversation::Turn)

    agent_run.catalog(catalog_version(agent_run), CATALOG_SKILLS) { Chat::Skill.available_to(agent_run.workspace) }
  end

  # What a turn's catalogue is built from: the workspace's connections, abilities and skills, the principal's grants as
  # resolved, and which of Firefight's own tools the workspace is offered. A block, so a held catalogue never reads it.
  def self.catalog_version(agent_run)
    lambda do
      workspace = agent_run.workspace
      principal = agent_run.acting_principal
      [ workspace.reach_version(principal), (granted(agent_run) if principal), FirefightTools.available_in(workspace).map(&:name_value) ]
    end
  end

  # The workspace's tools and the principal's grants are read once, since both lists need them.
  def self.build_catalog(agent_run)
    tools = switched_on_tools(agent_run)
    resolved = agent_run.acting_principal && granted(agent_run)
    firefight_entries(agent_run, resolved: resolved) + capability_entries(agent_run, tools: tools, resolved: resolved) +
      connection_entries(agent_run, tools: tools, resolved: resolved)
  end

  def self.firefight_entries(agent_run, resolved: nil)
    principal = agent_run.acting_principal
    workspace = agent_run.workspace
    offered = FirefightTools.available_in(workspace).reject { |tool_class| Groups::NOT_FOR_HALON.include?(tool_class.name_value.to_s) }
    keys = offered.to_h { |tool_class| [ tool_class, Ability::Action.system_key(*tool_class.authorization(workspace, {})) ] }
    actions = Ability::Action.system_actions.where(key: keys.values).index_by(&:key)
    # An open action, such as reading a public web page, is made the first time it is asked for.
    keys.values.uniq.each { |key| actions[key] ||= Ability::Action.lookup(key, workspace) if Ability::Action.open?(key) }

    keys.map do |tool_class, action_key|
      # A run that only reads is never handed one of Firefight's own tools that writes, whatever its principal was granted.
      writes = agent_run.reads_only? && !tool_class.annotations_value&.read_only_hint
      ready = !writes && principal.present? && principal.permitted_to?(actions[action_key], workspace, resolved: resolved)
      Entry.new(
        name: tool_class.name_value, description: clean(tool_class.description_value, ONE_LINE),
        state: (writes && STATE_READS_ONLY) || (ready ? STATE_READY : STATE_NOT_GRANTED),
        tool: (Firefight.new(agent_run, tool_class, actions[action_key]) if ready),
        group: Groups.of_firefight_tool(tool_class.name_value), source: Chat::Skill::SOURCE_FIREFIGHT, handle: tool_class.name_value.to_s
      )
    end
  end

  def self.connection_entries(agent_run, tools: switched_on_tools(agent_run), resolved: nil)
    principal = agent_run.acting_principal
    resolved ||= principal && granted(agent_run)

    # A provider tool a capability answers one to one is reached through the capability, so it is not offered twice,
    # and a connection tool that happens to share a capability's name is left out rather than shadowing it.
    packs = nil
    tools.reject { |tool| through_capability?(tool) }.map do |tool|
      writes = withheld_from?(agent_run, tool)
      ready = !writes && principal.present? && tool.callable_by?(principal, resolved)
      packs ||= changes_packs(tools) unless ready || writes
      Entry.new(
        name: tool.model_facing_name, description: clean([ (pack_needed(tool, packs) unless ready || writes), tool.described_for_agents ].compact.join(" "), ONE_LINE),
        state: (writes && STATE_READS_ONLY) || (ready ? STATE_READY : STATE_NOT_GRANTED),
        tool: (Connection.new(agent_run, tool) if ready),
        group: Groups.of_connection(tool.integration), source: tool.integration.provider, handle: tool.name
      )
    end
  end

  # A provider tool a capability answers one to one, or one sharing a capability's name, which is never offered itself.
  def self.through_capability?(tool)
    Integrations::Capabilities.wrapped?(tool) || Integrations::Capabilities.tool_names.include?(tool.model_facing_name)
  end

  # A tool that can change something on a run that only reads, unless its provider's read guard tells its reads apart.
  def self.withheld_from?(agent_run, tool) = agent_run.reads_only? && !tool.read_only? && Integrations::ReadGuards.for(tool).nil?

  # Leads a tool that changes something and is not granted, so the agent can tell the person which pack to ask for.
  # packs is each connection's changes pack by its id, when the caller read them for many tools at once. The tool is its
  # action's source, so it answers as Ability::Role.to_ask_for does.
  def self.pack_needed(tool, packs = nil)
    action = tool.ability_action
    pack = packs.nil? ? Ability::Role.to_ask_for(action) : (packs[tool.integration_id] if action && !action.read?)
    "Needs the #{pack.name} pack, which a workspace admin can give." if pack
  end

  # The pack Ability::Role.to_ask_for names, for every connection of these tools in one query.
  def self.changes_packs(tools)
    Ability::Role.where(integration_id: tools.map(&:integration_id).uniq, pack: Ability::Role::PACK_CHANGES).index_by(&:integration_id)
  end

  # One entry per capability some connection in the workspace can answer. It is ready when the principal may call at
  # least one tool it would run as, and the gateway still decides each call.
  def self.capability_entries(agent_run, tools: switched_on_tools(agent_run), resolved: nil)
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
    entries + key_query_entries(agent_run, offered) + log_pattern_entries(agent_run, offered) + [ what_changed_entry(agent_run, offered) ]
  end

  # what_changed, offered whatever is connected, since the map's own changes and the activity log need no connection.
  # It reads runs live through run history when a connection answers it.
  def self.what_changed_entry(agent_run, offered)
    history = offered.find { |spec, _able, _callable| spec.key == Integrations::Capabilities::HISTORY }
    ready = agent_run.acting_principal.present?
    Entry.new(
      name: WhatChanged::NAME, description: clean(ResourceMap::Timeline::DESCRIPTION, ONE_LINE), state: ready ? STATE_READY : STATE_NOT_GRANTED,
      tool: (WhatChanged.new(agent_run, history) if ready), group: Groups::MAP, source: Chat::Skill::SOURCE_FIREFIGHT, handle: WhatChanged::NAME
    )
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
