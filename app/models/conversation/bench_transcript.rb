# What happened in a replayed chat, read back from its record: what the person said, each call Halon made with whether
# it only read, whether it waited for the person and what they decided, and what Halon replied. The score counts from
# it and the judge reads it as text.
class Conversation::BenchTranscript
  Call = Data.define(:name, :arguments, :reads, :approval, :recorded, :failed, :result) do
    def asked? = approval.present?

    # Turned down, or moved past while it waited, so it never ran.
    def ran? = [ Chat::APPROVAL_DENIED, Chat::APPROVAL_WITHDRAWN, Chat::APPROVAL_REQUESTED ].exclude?(approval)
  end
  Entry = Data.define(:said_by, :text, :call)

  PERSON = :person
  HALON = :halon
  CALL = :call

  DECISION_WORDS = {
    Chat::APPROVAL_REQUESTED => "it waited for the person to confirm, and they did not answer",
    Chat::APPROVAL_APPROVED => "it waited for the person to confirm, and they approved",
    Chat::APPROVAL_DENIED => "it waited for the person to confirm, and they said no",
    Chat::APPROVAL_WITHDRAWN => "it waited for the person to confirm, and they said something else instead"
  }.freeze

  # A tool result is cut to this in the text the judge reads, which is enough to see what a call showed.
  RESULT_SHOWN = 1_500

  attr_reader :entries

  def initialize(chat, bench_case)
    @case = bench_case
    @entries = chat.messages.includes(ruby_llm_tool_calls: :result).flat_map { |message| entries_of(message) }
  end

  def calls = entries.filter_map(&:call)

  def replies = entries.select { |entry| entry.said_by == HALON }.map(&:text)

  def confirmations = calls.select(&:asked?)

  # A confirmation for a call that only read was never needed, since reading changes nothing.
  def unneeded_confirmations = confirmations.select(&:reads)

  def not_recorded = calls.count { |call| !call.recorded }

  def called?(name) = calls.any? { |call| call.name == name && call.ran? }

  def cites_any?(texts) = texts.any? { |text| replies.any? { |reply| reply.downcase.include?(text.downcase) } }

  def answer = replies.join("\n\n")

  def to_text
    entries.map do |entry|
      case entry.said_by
      when PERSON then "Person: #{entry.text}"
      when HALON then "Agent: #{entry.text}"
      else call_text(entry.call)
      end
    end.join("\n\n")
  end

  private

  def entries_of(message)
    return [] if message.nudge || message.role == Chat::Message::ROLE_SYSTEM || message.role == Chat::Message::ROLE_TOOL
    return [ Entry.new(said_by: PERSON, text: message.content.to_s, call: nil) ] if message.role == Chat::Message::ROLE_USER

    spoken = message.content.present? ? [ Entry.new(said_by: HALON, text: message.content.to_s, call: nil) ] : []
    spoken + message.ruby_llm_tool_calls.sort_by(&:created_at).map { |call| Entry.new(said_by: CALL, text: nil, call: call_of(call)) }
  end

  def call_of(call)
    arguments = call.arguments.to_h.stringify_keys
    result = call.result&.content.to_s
    Call.new(
      name: call.name, arguments: arguments, reads: reads?(call.name, arguments), approval: call.approval,
      recorded: result != Conversation::BenchCase::NOT_RECORDED, failed: call.failed, result: result
    )
  end

  def reads?(name, arguments)
    @case.tool(name)&.reads?(arguments) || @case.answers.any? { |answer| answer.reads && answer.matches?(name, arguments) }
  end

  def call_text(call)
    kind = call.reads ? "a read" : "a change"
    lines = [ "Agent called #{call.name} #{call.arguments.to_json} (#{kind})" ]
    lines << "  #{DECISION_WORDS.fetch(call.approval)}" if call.asked?
    lines << "  It returned: #{call.result.truncate(RESULT_SHOWN)}" if call.ran? && call.result.present?
    lines.join("\n")
  end
end
