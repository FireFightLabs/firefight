# What happened in a replayed chat, read back from its record: what the person said, each call Halon made with whether
# it only read, whether it waited for the person and what they decided, and what Halon replied. The score counts from
# it and the judge reads it as text.
class Conversation::BenchTranscript
  # by names the specialist that made a call for Halon, nil for Halon's own.
  Call = Data.define(:name, :arguments, :reads, :approval, :recorded, :failed, :result, :by) do
    def initialize(by: nil, **) = super

    def asked? = approval.present?

    # Turned down, or moved past while it waited, so it never ran.
    def ran? = [ Chat::APPROVAL_DENIED, Chat::APPROVAL_WITHDRAWN, Chat::APPROVAL_REQUESTED ].exclude?(approval)
  end
  Entry = Data.define(:said_by, :text, :call)

  PERSON = :person
  HALON = :halon
  CALL = :call
  # What the reply before it lists as read, as the dashboard and a thread show under an answer.
  SOURCES = :sources

  DECISION_WORDS = {
    Chat::APPROVAL_REQUESTED => "it waited for the person to confirm, and they did not answer",
    Chat::APPROVAL_APPROVED => "it waited for the person to confirm, and they approved",
    Chat::APPROVAL_DENIED => "it waited for the person to confirm, and they said no",
    Chat::APPROVAL_WITHDRAWN => "it waited for the person to confirm, and they said something else instead"
  }.freeze

  # A tool result is cut to this in the text the judge reads, which is enough to see what a call showed.
  RESULT_SHOWN = 1_500

  attr_reader :entries

  # unscripted holds the ids of the calls nothing in the case answered. sources lists what each reply that ended a turn
  # shows as read, by the reply's id, each with a title and a url or nil (Chat::Sources).
  def initialize(chat, bench_case, unscripted: Set.new, sources: {})
    @case = bench_case
    @unscripted = unscripted
    @sources = sources
    @entries = chat.messages.includes(ruby_llm_tool_calls: :result).flat_map { |message| entries_of(message) }
    @charts = chat.charts.to_a
  end

  # The charts the replay drew that no reply placed by its marker (Chat::Chart::Marker), which follow the answer
  # rather than sit beside what they show.
  def unplaced_charts
    placed = replies.flat_map { |reply| Chat::Chart::Marker.handles_in(reply) }
    @charts.reject { |chart| placed.include?(chart.handle) }
  end

  # Every address the answers list as read, which counts as citing them as a link in the words does.
  def source_links = @sources.values.flatten.filter_map(&:url)

  def calls = entries.filter_map(&:call)

  def replies = entries.select { |entry| entry.said_by == HALON }.map(&:text)

  def confirmations = calls.select(&:asked?)

  # A confirmation for a call that only read was never needed, since reading changes nothing.
  def unneeded_confirmations = confirmations.select(&:reads)

  def not_recorded = calls.count { |call| !call.recorded }

  def called?(name) = calls.any? { |call| call.name == name && call.ran? }

  def cites_any?(texts)
    shown = replies + source_links
    texts.any? { |text| shown.any? { |cited| cited.downcase.include?(text.downcase) } }
  end

  # The calls still waiting for the person when the chat ended, which is how a turn that stopped to ask ends.
  def waiting = confirmations.select { |call| call.approval == Chat::APPROVAL_REQUESTED }

  # What the person was left with: Halon's replies, or the confirmation it stopped on when it wrote none.
  def answer
    return replies.join("\n\n") if replies.any?
    return "" if waiting.empty?

    "Waiting for the person to confirm #{waiting.map(&:name).uniq.to_sentence}."
  end

  def to_text
    entries.map do |entry|
      case entry.said_by
      when PERSON then "Person: #{entry.text}"
      when HALON then "Agent: #{entry.text}"
      when SOURCES then "Listed under that answer as read: #{entry.text}"
      else call_text(entry.call)
      end
    end.join("\n\n")
  end

  private

  def entries_of(message)
    return [] if message.nudge || message.role == Chat::Message::ROLE_SYSTEM || message.role == Chat::Message::ROLE_TOOL
    return [ Entry.new(said_by: PERSON, text: message.content.to_s, call: nil) ] if message.role == Chat::Message::ROLE_USER

    spoken = message.content.present? ? [ Entry.new(said_by: HALON, text: message.content.to_s, call: nil), *sources_entry(message) ] : []
    spoken + message.ruby_llm_tool_calls.sort_by(&:created_at).flat_map do |call|
      [ Entry.new(said_by: CALL, text: nil, call: call_of(call)), *specialist_entries(message, call) ]
    end
  end

  def sources_entry(message)
    listed = @sources[message.id]
    return [] if listed.blank?

    [ Entry.new(said_by: SOURCES, text: listed.map { |source| [ source.title, source.url ].compact.join(" ") }.join("; "), call: nil) ]
  end

  # What the specialists an ask_specialist call started read for Halon, each after the call that asked them, so the score
  # and the judge see every read the answer rests on. Their report goes back to Halon as the call's own result.
  def specialist_entries(message, call)
    return [] unless call.name == Chat::Helper::ASK_SPECIALIST

    Chat::Helper.where(chat_id: message.chat_id, tool_call_id: call.tool_call_id).where.not(domain: nil).in_order.includes(:own_chat).flat_map do |helper|
      next [] unless helper.own_chat

      by = helper.domain.tr("_", " ")
      helper.own_chat.tool_calls.where.not(name: Chat::Helper::REPORT_FINDINGS).includes(:result).order(:created_at, :id).map do |read|
        Entry.new(said_by: CALL, text: nil, call: call_of(read, by: by))
      end
    end
  end

  def call_of(call, by: nil)
    arguments = call.arguments.to_h.stringify_keys
    result = call.result&.content.to_s
    Call.new(
      name: call.name, arguments: arguments, reads: call.name == Chat::Theory::TOOL || reads?(call.name, arguments), approval: call.approval,
      recorded: @unscripted.exclude?(call.tool_call_id), failed: call.failed, result: result, by: by
    )
  end

  def reads?(name, arguments)
    @case.tool(name)&.reads?(arguments) || @case.answers.any? { |answer| answer.reads && answer.matches?(name, arguments) }
  end

  def call_text(call)
    return "Agent updated its #{call.result.presence || 'theory board'}" if call.name == Chat::Theory::TOOL

    kind = call.reads ? "a read" : "a change"
    who = call.by ? "The #{call.by} specialist, for the agent," : "Agent"
    lines = [ "#{who} called #{call.name} #{call.arguments.to_json} (#{kind})" ]
    lines << "  #{DECISION_WORDS.fetch(call.approval)}" if call.asked?
    lines << "  It returned: #{call.result.truncate(RESULT_SHOWN)}" if call.ran? && call.result.present?
    lines.join("\n")
  end
end
