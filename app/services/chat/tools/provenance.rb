# Where a change Halon proposes may have come from. Text Halon reads from outside, such as an issue, a log line, a web
# page or any provider's answer, can carry words written to steer it. So once a chat has read any, Allow for the rest of
# this chat no longer covers a change, and each change it asks about says what was read. The rule rests on what was read,
# never on what the text says, so no wording gets past it. Every answer counts as outside except Halon's own bookkeeping
# and memory and Firefight's tools that declare they hold only the workspace's own words (Mcp::Tools::Base.own_words). A
# file a person attached counts too, since a pasted log is still outside text.
module Chat::Tools::Provenance
  # The most reads a question names. The rest are counted.
  SHOWN = 5
  # Values any change of its kind holds, which say nothing about where this one came from: a request's method, a flag
  # and a plain number. Anything else counts, so a short name such as web is the change's own.
  GENERIC_TOKENS = %w[get post put patch delete head options true false null none yes no].to_set.freeze
  PLAIN_NUMBER = /\A[-+]?\d+(\.\d+)?\z/
  LINE_SHORTEST = 12
  VALUE_SHOWN = 80
  SOURCES = "sources".freeze
  LABEL = "label".freeze
  FOUND = "found".freeze
  FROM = "from".freeze
  OTHERS = "others".freeze

  # from says where the text came from in a few words, such as "Northflank's docs", nil on a call asked before it was kept.
  Source = Data.define(:label, :found, :from) do
    def initialize(from: nil, **) = super
  end
  Read = Data.define(:sources, :others)

  WEB = "the web".freeze
  ATTACHED = "a file attached to this chat".freeze
  COMMAND = "a command's output".freeze

  def self.own_words_names
    @own_words_names ||= [
      *Chat::Tools.internal_names,
      *[ Chat::Tools::Recall, Chat::Tools::Remember, Chat::Tools::DisputeMemory, Chat::Tools::CorrectMemory ].map(&:tool_name),
      *[ Conversation::Tools::ListWatches, Conversation::Tools::StopWatch, Conversation::Tools::ExtendWatch ].map(&:tool_name),
      Chat::Tools::Theories.tool_name,
      *Mcp::Tools.all.select(&:own_words?).map { |tool_class| tool_class.name_value.to_s }
    ].to_set.freeze
  end

  # Whether anything from outside has reached this chat's model.
  def self.read_outside?(chat)
    return false unless chat

    outside_calls(chat).exists? || chat.attached_files.exists?
  end

  # Whether a tool the person allowed for the rest of the chat still runs without asking. Only until something outside
  # has been read.
  def self.allowed?(agent_run, tool_name)
    chat = agent_run.chat
    chat.present? && chat.allows_tool?(tool_name) && !read_outside?(chat)
  end

  # Kept with each call put to the person, so the question says what was read before it however often it is redrawn,
  # and Allow for the rest of this chat is never offered or honoured for it (Chat#decide!).
  def self.record!(agent_run, tool_calls)
    chat = agent_run.chat
    return if tool_calls.empty? || !read_outside?(chat)

    tool_calls.each do |tool_call|
      read = of(chat, tool_call, agent_run.workspace)
      tool_call.update_columns(provenance: {
        SOURCES => read.sources.map { |source| { LABEL => source.label, FOUND => source.found, FROM => source.from } }, OTHERS => read.others
      })
    end
  end

  # What was read before the call, those holding one of the call's own values first, since that is where the idea most
  # likely came from. A value the person wrote themselves is theirs, so it points at nothing read.
  def self.of(chat, tool_call, workspace)
    values = values_of(tool_call.arguments, person_words(chat))
    reads = outside_calls(chat).includes(:result).order(:created_at, :id).filter_map do |call|
      next if call.tool_call_id == tool_call.tool_call_id

      text = call.result&.content.to_s
      Source.new(label: Chat::Tools.label(call.name, call.arguments, workspace: workspace).presence || call.name, found: values.select { |value| mentions?(text, value) },
                 from: from(call, workspace))
    end
    reads += chat.attached_files.map do |file|
      Source.new(label: "File attached: #{file.filename}", found: values.select { |value| mentions?(file.text.to_s, value) }, from: ATTACHED)
    end

    found, rest = reads.partition { |source| source.found.any? }
    shown = (found + rest.reverse).first([ SHOWN, found.size ].max)
    Read.new(sources: shown.map { |source| source.with(found: source.found.map { |value| value.truncate(VALUE_SHOWN) }) }, others: reads.size - shown.size)
  end

  # What the stored provenance says, or nil for a call asked before anything outside was read. A value kept before
  # generic ones were left out is left out here too, so an older question reads the same as a new one.
  def self.stored(tool_call)
    kept = tool_call.try(:provenance)
    return nil if kept.blank?

    sources = Array(kept[SOURCES]).map do |source|
      Source.new(label: source[LABEL].to_s, found: Array(source[FOUND]).select { |value| specific?(value) }, from: source[FROM].presence)
    end
    Read.new(sources: sources, others: kept[OTHERS].to_i)
  end

  # Whether a value is this change's own, such as a service's name, an id or an address, rather than one any change of
  # its kind holds, such as POST or true.
  def self.specific?(value)
    text = value.to_s.strip
    text.present? && !GENERIC_TOKENS.include?(text.downcase) && !text.match?(PLAIN_NUMBER)
  end

  # Whether text names a value as a whole, so web is found in "restart web" but not inside website or dev-web.
  def self.mentions?(text, value)
    text.match?(/(?<![[:alnum:]_-])#{Regexp.escape(value)}(?![[:alnum:]_-])/)
  end

  # Where a read's text came from, in a few words the confirmation names it by.
  def self.from(call, workspace)
    name = call.name.to_s
    arguments = call.arguments.to_h.stringify_keys
    return "#{Chat::Tools::Docs.provider_name(arguments['provider'])}'s docs" if [ Chat::Tools::Docs::SEARCH, Chat::Tools::Docs::READ ].include?(name) && arguments["provider"].present?
    return WEB if [ Chat::Tools::Web::SEARCH, Chat::Tools::Web::READ, Chat::Tools::Browser::NAME, Chat::Tools::OutsideCheck::NAME ].include?(name)
    return COMMAND if name == Chat::Tools::Terminal::NAME
    return skill_from(arguments) if name == Chat::Tools::UseSkill.tool_name

    tool = workspace && Chat::Tools::Target.label(workspace, name)
    return "an answer from #{tool.integration.display_name}" if tool

    "the result of #{Chat::Tools.title_for(name, nil).downcase_first}"
  end

  def self.skill_from(arguments)
    skill = Chat::Skill.find(arguments["skill"])
    return "a skill's steps" unless skill
    return "a Firefight skill's steps" if skill.firefight?

    provider = Chat::Tools::Docs.provider_name(skill.source)
    arguments["reference"].present? ? "#{provider}'s docs" : "a #{provider} skill's steps"
  end

  def self.outside_calls(chat)
    chat.tool_calls.where.not(result_id: nil).where.not(name: own_words_names.to_a)
  end

  def self.person_words(chat)
    chat.readable_messages.where(role: Chat::Message::ROLE_USER).map(&:content).join("\n")
  end

  # Each text the change was given, and each long line of a longer one such as a script, so a command copied from a log
  # is found even inside a bigger one.
  def self.values_of(arguments, said)
    texts = leaves(arguments.to_h.stringify_keys.except(*Chat::Tools::FOR_PERSON, Chat::Tools::LookFirst::BECAUSE, Integration::Tool::ENVIRONMENT_ARG))
    texts += texts.flat_map { |text| text.lines.map(&:strip).select { |line| line.length >= LINE_SHORTEST } }
    texts.map(&:strip).uniq.select { |text| specific?(text) && !mentions?(said, text) }
  end

  def self.leaves(value)
    case value
    when Hash then value.values.flat_map { |inner| leaves(inner) }
    when Array then value.flat_map { |inner| leaves(inner) }
    when String then [ value ]
    else []
    end
  end
  private_class_method :outside_calls, :person_words, :values_of, :leaves, :from, :skill_from, :mentions?
end
