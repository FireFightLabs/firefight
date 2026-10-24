# What each step of a run did, in the order it happened, worked out once for the whole run so the run's view shows a
# step's work as it goes and keeps it as its log afterwards: every gateway call the step made with how it ended, each
# tool Halon called in the step's chat, and for a watch every line it said and each new thing it saw. now is the step's
# work in one line while it goes. The rows it reads are loaded for every step at once, so a run of many steps reads
# each kind of row once. describe_tool names a tool Halon called as its chat does, given the tool's name and arguments.
class Workflow::Run::Activity
  TONE_NEUTRAL = "neutral".freeze
  TONE_GOOD = "good".freeze
  TONE_BAD = "bad".freeze
  TONE_WAITING = "waiting".freeze
  TONES = [ TONE_NEUTRAL, TONE_GOOD, TONE_BAD, TONE_WAITING ].freeze

  # One line of a step's log. until and count are set when it stands for several of the same call in a row, such as a
  # watch reading the same thing each minute. repeats is what such calls share, nil for a line that never folds.
  Entry = Data.define(:id, :at, :until_at, :count, :text, :detail, :tone, :repeats) do
    def initialize(repeats: nil, **rest) = super

    def to_h = { id: id, at: at.utc.iso8601, until: until_at&.utc&.iso8601, count: count, text: text, detail: detail, tone: tone }
  end

  # Where a watch the step keeps stands: what it follows, how often it read, when it reads next and when it gives up.
  Watching = Data.define(:active, :headline, :reads, :basis, :checked_at, :next_check_at, :expires_at, :steps) do
    def to_h
      { active: active, headline: headline, reads: reads, basis: basis, checkedAt: checked_at&.utc&.iso8601, nextCheckAt: next_check_at&.utc&.iso8601,
        expiresAt: expires_at.utc.iso8601, steps: steps }
    end
  end

  DETAIL_LIMIT = 2_000
  DECISION_WORDS = {
    Ability::Invocation::DECISION_ALLOW => "Allowed", Ability::Invocation::DECISION_DENY => "Refused",
    Ability::Invocation::DECISION_PENDING => "Held for approval"
  }.freeze
  WATCH_TONES = {
    Chat::Watch::Update::KIND_PART_FAILED => TONE_BAD, Chat::Watch::Update::KIND_SLOW => TONE_WAITING,
    Chat::Watch::Update::KIND_CEILING => TONE_WAITING, Chat::Watch::Update::KIND_HANDED_BACK => TONE_WAITING
  }.freeze
  WATCH_ENDED_TONES = {
    Chat::Watch::STATUS_SUCCEEDED => TONE_GOOD, Chat::Watch::STATUS_FAILED => TONE_BAD, Chat::Watch::STATUS_TIMED_OUT => TONE_WAITING,
    Chat::Watch::STATUS_STOPPED => TONE_NEUTRAL
  }.freeze
  GOING = [ DefinedWorkflow::STEP_RUNNING, DefinedWorkflow::STEP_WAITING ].freeze
  ENDED_WORDS = {
    DefinedWorkflow::STEP_SUCCEEDED => "Done.", DefinedWorkflow::STEP_FAILED => "Failed.", DefinedWorkflow::STEP_SKIPPED => "Skipped itself.",
    DefinedWorkflow::STEP_CANCELLED => "Cancelled."
  }.freeze
  ENDED_TONES = {
    DefinedWorkflow::STEP_SUCCEEDED => TONE_GOOD, DefinedWorkflow::STEP_FAILED => TONE_BAD, DefinedWorkflow::STEP_SKIPPED => TONE_NEUTRAL,
    DefinedWorkflow::STEP_CANCELLED => TONE_NEUTRAL
  }.freeze

  def initialize(run, describe_tool:)
    @run = run
    @describe_tool = describe_tool
  end

  # The gateway's record of each call the step made, oldest first.
  def calls_for(row) = calls.fetch([ row.step_key, row.iteration.presence ], [])

  def log_for(row)
    entries = [ started(row), *calls_for(row).map { |call| call_entry(call) }, *halon_entries(row), *watch_entries(row), answered(row), ended(row) ].compact
    grouped(entries.sort_by.with_index { |entry, index| [ entry.at, index ] }).map(&:to_h)
  end

  # What it is doing right now, in one line, or nil once it ended or when there is nothing more to say than its state.
  def now_for(row)
    return unless GOING.include?(row.status)

    watch = watch_of(row)
    return watch_now(watch) if watch&.active?
    return "It waits for an approver to allow what it called." if row.status == DefinedWorkflow::STEP_WAITING && row_waiting_approval?(row)

    in_flight = calls_for(row).reverse.find { |call| call.decision == Ability::Invocation::DECISION_ALLOW && !call.finished? }
    return "Calling #{call_words(in_flight)}." if in_flight
    return "Calling #{asked_tool(row)}, waiting for its answer." if asked_tool(row) && row.status == DefinedWorkflow::STEP_RUNNING

    halon_now(row)
  end

  def watching_for(row)
    watch = watch_of(row)
    return unless watch

    Watching.new(
      active: watch.active?, headline: Chat::Watch::Shown.headline(watch), reads: Chat::Watch::Shown.reads(watch), basis: Chat::Watch::Shown.basis(watch),
      checked_at: watch.checked_at, next_check_at: next_check(watch), expires_at: watch.expires_at,
      steps: watch.steps.map do |step|
        { id: step.id, label: step.label, status: Chat::Watch::Shown.step_status(step), line: Chat::Watch::Shown.step_line(step), url: step.run_url,
          readAt: step.read_at&.utc&.iso8601, lastSeen: step.last_state&.truncate(DETAIL_LIMIT) }
      end
    ).to_h
  end

  def waiting_approval?(row) = row.status == DefinedWorkflow::STEP_WAITING && row_waiting_approval?(row)

  private

  def calls
    @calls ||= @run.invocations.includes(:approval).order(:created_at, :id).to_a.group_by { |call| [ call.workflow_step_key, call.workflow_iteration.presence ] }
  end

  def chats
    @chats ||= Chat.where(owner_type: Workflow::Run::Step.name, owner_id: @run.steps.map(&:id))
                   .includes(messages: { ruby_llm_tool_calls: :result }, watches: %i[steps updates]).index_by(&:owner_id)
  end

  def chat_of(row) = chats[row.id]

  def watch_of(row) = chat_of(row)&.watches&.last

  def row_waiting_approval?(row)
    calls_for(row).any? { |call| call.decision == Ability::Invocation::DECISION_PENDING && call.approval&.pending? }
  end

  # About when the watch reads next: once a minute, later when it spaces its reads to keep under its ceiling, never past
  # when it gives up.
  def next_check(watch)
    return unless watch.active?

    due = [ watch.checked_at && watch.checked_at + Chat::Watch::CHECK_EVERY, watch.next_check_at ].compact.max || Time.current
    [ due, watch.expires_at ].min
  end

  # The thing the watch is on, in the words its card gives that thing, such as which deploy it waits for, with how many
  # are done when it follows more than one.
  def watch_now(watch)
    steps = watch.steps.to_a
    current = steps.find { |step| !step.over? && step.ready? } || steps.find { |step| !step.over? }
    return Chat::Watch::Shown.why(watch) unless current

    now = "#{current.label}: #{Chat::Watch::Shown.step_line(current)}"
    steps.size > 1 ? "#{steps.count(&:over?)} of #{steps.size} done. #{now}" : now
  end

  def started(row)
    return unless row.started_at

    Entry.new(id: "#{row.id}-started", at: row.started_at, until_at: nil, count: 1, text: "Started.", detail: nil, tone: TONE_NEUTRAL)
  end

  def ended(row)
    words = ENDED_WORDS[row.status]
    return unless words && row.finished_at

    took = " It took the #{row.route.tr('_', ' ')} way." if row.route.present? && row.status == DefinedWorkflow::STEP_SUCCEEDED
    detail = row.error.presence || row.note
    Entry.new(id: "#{row.id}-ended", at: row.finished_at, until_at: nil, count: 1, text: "#{words}#{took}", detail: detail, tone: ENDED_TONES.fetch(row.status))
  end

  def call_words(call) = call.action_key

  # The tool a Call a tool step calls, which hands back its answer whether or not the gateway kept a row for the call.
  def asked_tool(row) = row.input.to_h[DefinedWorkflow::Steps::CallTool::KEY_TOOL].presence

  def answered(row)
    answer = row.output.to_h[DefinedWorkflow::Steps::CallTool::OUTPUT_ANSWER]
    return unless asked_tool(row) && answer.present? && row.finished_at

    Entry.new(id: "#{row.id}-answered", at: row.finished_at, until_at: nil, count: 1, text: "#{asked_tool(row)} answered.",
              detail: answer.to_s.truncate(DETAIL_LIMIT), tone: TONE_GOOD)
  end

  def call_entry(call)
    going = call.decision == Ability::Invocation::DECISION_ALLOW && !call.finished?
    text = call.source == Chat::Watch::SOURCE ? "Read #{call_words(call)}" : "Called #{call_words(call)}"
    Entry.new(id: call.id, at: call.created_at, until_at: nil, count: 1, text: going ? "#{text}, waiting for its answer" : text,
              detail: call_detail(call), tone: call_tone(call, going), repeats: ([ text, call.decision, call.outcome, call.error_summary ] unless going))
  end

  def call_detail(call)
    words = DECISION_WORDS.fetch(call.decision)
    words += ", the approval is #{call.approval.status}" if call.approval && call.decision == Ability::Invocation::DECISION_PENDING
    words += ", ended in #{call.outcome}" if call.outcome
    words += " after #{call.duration_ms} ms" if call.duration_ms
    [ "#{words}.", call.error_summary.presence ].compact.join(" ")
  end

  def call_tone(call, going)
    return TONE_WAITING if going || call.decision == Ability::Invocation::DECISION_PENDING
    return TONE_BAD if call.decision == Ability::Invocation::DECISION_DENY || (call.outcome && !call.succeeded?)

    TONE_GOOD
  end

  # The same call made again and again in a row with the same result reads as one line with how many times and when.
  def grouped(entries)
    entries.chunk_while { |earlier, later| earlier.repeats && earlier.repeats == later.repeats }
           .map do |run|
             next run.first if run.size == 1

             run.first.with(until_at: run.last.at, count: run.size, detail: run.last.detail)
           end
  end

  def tool_calls(row)
    chat = chat_of(row)
    return [] unless chat

    chat.messages.flat_map(&:ruby_llm_tool_calls).sort_by(&:created_at)
  end

  def halon_entries(row)
    tool_calls(row).filter_map do |call|
      step = @describe_tool.call(call.name, call.arguments)
      next unless step

      outcome = Chat::StepOutcome.for_call(call, chat_of(row))
      tone = if call.failed then TONE_BAD
      elsif call.result_id.present? then TONE_GOOD
      else TONE_WAITING
      end
      detail = [ step.headline.presence, outcome&.said.presence || outcome&.lines&.join("\n").presence ].compact.join("\n").truncate(DETAIL_LIMIT).presence
      Entry.new(id: call.id, at: call.created_at, until_at: nil, count: 1, text: "Halon: #{step.title}", detail: detail, tone: tone)
    end
  end

  def halon_now(row)
    chat = chat_of(row)
    return unless chat

    going = tool_calls(row).reverse.find { |call| call.result_id.blank? && !call.failed }
    step = going && @describe_tool.call(going.name, going.arguments)
    step ? "Halon: #{step.title}." : "Halon is thinking."
  end

  def watch_entries(row)
    watch = watch_of(row)
    return [] unless watch

    said = watch.updates.map do |update|
      tone = update.kind == Chat::Watch::Update::KIND_ENDED ? WATCH_ENDED_TONES.fetch(update.ended_as || watch.status, TONE_NEUTRAL) : WATCH_TONES.fetch(update.kind, TONE_NEUTRAL)
      Entry.new(id: update.id, at: update.created_at, until_at: nil, count: 1, text: update.text, detail: nil, tone: tone)
    end
    seen = watch.steps.flat_map do |step|
      step.recent_readings.each_with_index.filter_map do |(at, text), index|
        next unless at

        Entry.new(id: "#{step.id}-#{index}", at: at, until_at: nil, count: 1, text: "#{step.label}: saw something new", detail: text.truncate(DETAIL_LIMIT), tone: TONE_NEUTRAL)
      end
    end
    said + seen
  end
end
