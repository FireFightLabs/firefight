# Where a change Halon proposes may have come from. Text Halon reads from outside, such as an issue, a log line, a web
# page or any provider's answer, can carry words written to steer it. So once a chat has read any, Allow for the rest of
# this chat no longer covers a change, and each change it asks about says what was read. The rule rests on what was read,
# never on what the text says, so no wording gets past it. Every answer counts as outside except Halon's own bookkeeping
# and memory and Firefight's tools that declare they hold only the workspace's own words (Mcp::Tools::Base.own_words). A
# file a person attached counts too, since a pasted log is still outside text.
module Chat::Tools::Provenance
  # The most reads a question names. The rest are counted.
  SHOWN = 5
  # A value of the change shorter than this is too common to say where it came from.
  SHORTEST_VALUE = 4
  LINE_SHORTEST = 12
  VALUE_SHOWN = 80
  SOURCES = "sources".freeze
  LABEL = "label".freeze
  FOUND = "found".freeze
  OTHERS = "others".freeze

  Source = Data.define(:label, :found)
  Read = Data.define(:sources, :others)

  def self.own_words_names
    @own_words_names ||= [
      *Chat::Tools.internal_names,
      *[ Chat::Tools::Recall, Chat::Tools::Remember, Chat::Tools::DisputeMemory, Chat::Tools::CorrectMemory ].map(&:tool_name),
      *[ Conversation::Tools::ListWatches, Conversation::Tools::StopWatch, Conversation::Tools::ExtendWatch ].map(&:tool_name),
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
        SOURCES => read.sources.map { |source| { LABEL => source.label, FOUND => source.found } }, OTHERS => read.others
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
      Source.new(label: Chat::Tools.label(call.name, call.arguments, workspace: workspace).presence || call.name, found: values.select { |value| text.include?(value) })
    end
    reads += chat.attached_files.map { |file| Source.new(label: "File attached: #{file.filename}", found: values.select { |value| file.text.to_s.include?(value) }) }

    found, rest = reads.partition { |source| source.found.any? }
    shown = (found + rest.reverse).first([ SHOWN, found.size ].max)
    Read.new(sources: shown.map { |source| source.with(found: source.found.map { |value| value.truncate(VALUE_SHOWN) }) }, others: reads.size - shown.size)
  end

  # What the stored provenance says, or nil for a call asked before anything outside was read.
  def self.stored(tool_call)
    kept = tool_call.try(:provenance)
    return nil if kept.blank?

    Read.new(sources: Array(kept[SOURCES]).map { |source| Source.new(label: source[LABEL].to_s, found: Array(source[FOUND])) }, others: kept[OTHERS].to_i)
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
    texts = leaves(arguments.to_h.stringify_keys.except(Chat::Tools::INTENT_ARG, Integration::Tool::ENVIRONMENT_ARG))
    texts += texts.flat_map { |text| text.lines.map(&:strip).select { |line| line.length >= LINE_SHORTEST } }
    texts.map(&:strip).uniq.select { |text| text.length >= SHORTEST_VALUE && !said.include?(text) }
  end

  def self.leaves(value)
    case value
    when Hash then value.values.flat_map { |inner| leaves(inner) }
    when Array then value.flat_map { |inner| leaves(inner) }
    when String then [ value ]
    else []
    end
  end
  private_class_method :outside_calls, :person_words, :values_of, :leaves
end
