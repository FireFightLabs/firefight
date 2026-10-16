# One turn of a conversation: the agent reads the question, uses what it can reach, and replies.
class Conversation::Runner
  NO_ROOM_LEFT = "I could not finish that one. Ask me something narrower, or start an investigation.".freeze
  STOPPED = "Stopped.".freeze
  # What the model is told for a tool it asked for and never got, so the chat stays one a provider accepts.
  STOPPED_BEFORE_RUNNING = "Not run. The person stopped this answer first.".freeze
  # What the model is told for a tool the person stopped while it ran, whose answer never came back.
  STOPPED_WHILE_RUNNING = "Stopped by the person while it ran, so nothing came back. Whether a change it was making took effect is unknown.".freeze
  PHASE_EVENT = "conversation_reply.phase".freeze
  FIRST_TEXT_EVENT = "conversation_reply.first_text".freeze
  PHASE_SETUP = "setup".freeze
  PHASE_CONTEXT = "context".freeze
  PHASE_RESPONDER = "responder".freeze
  PHASE_AFTER = "after".freeze
  # Each step of setup, logged under SETUP_STEP_EVENT with how long it took and how many queries it sent.
  SETUP_STEP_EVENT = "conversation_reply.setup_step".freeze
  STEP_CHAT = "chat".freeze
  STEP_HAND_BACK_ROOM = "hand_back_room".freeze
  STEP_DISCARD = "discard_interrupted".freeze
  STEP_CLOSE_CALLS = "close_unfinished_calls".freeze
  STEP_TAKE_QUEUED = "take_queued".freeze
  STEP_HELD_CALL = "held_call".freeze
  STEP_PULL_REQUEST_FIX = "pull_request_fix".freeze
  STEP_CODE_PAUSE = "code_pause".freeze
  STEP_PLAN_NOTE = "plan_note".freeze
  STEP_HAND_BACK_NOTE = "hand_back_note".freeze
  STEP_ANSWERED_ALREADY = "answered_already".freeze
  STEP_DELIVERED = "delivered".freeze
  STEP_EXPECT_REPLY = "expect_reply".freeze
  STEP_STOP_REQUESTED = "stop_requested".freeze
  STEP_STOPPED = "stopped".freeze
  STEP_THINKING = "thinking".freeze
  STEP_LISTENERS = "listeners".freeze
  STEP_HELD_OUTCOMES = "held_outcomes".freeze
  STEP_CATCH_UP = "catch_up".freeze
  STEP_SPECIALISTS = "specialists".freeze
  STEP_PRESENTED = "presented".freeze
  STEP_SUSPECTS = "suspects".freeze

  # held_call is an approved call someone pressed Run on, which this turn runs first. handed_back is a watch step that
  # could not find what it followed, which this turn re-plans, reading only. pull_request_fix is a pull request notice
  # someone pressed Fix it on, whose code change this turn runs first. code_pause is a code change paused at its spending
  # limit that someone pressed Continue on, which this turn carries on first. plan is a plan whose time came or that
  # someone pressed Retry or Undo on, as plan_move says, which this turn carries out.
  def initialize(conversation, asker:, held_call: nil, handed_back: nil, pull_request_fix: nil, code_pause: nil, plan: nil, plan_move: nil)
    @conversation = conversation
    approved = plan if plan_move == Conversation::Plans::MOVE_RUN
    @turn = Conversation::Turn.new(conversation, asker: asker, reads_only: handed_back.present?, approved_plan: approved)
    @plan = plan
    @plan_move = plan_move
    @held_call = held_call
    @handed_back = handed_back
    @pull_request_fix = pull_request_fix
    @code_pause = code_pause
    @progress_lock = Mutex.new
  end

  def run
    @marked = @turn_started_at = Time.current
    @turn.hold_catalog!
    @conversation.workspace.hold_reads!
    chat, purse, presented, suspects = timed_phase(PHASE_SETUP) do
      chat = setup_step(STEP_CHAT) { @conversation.chat_record }
      # One workspace for the whole turn, so what it memoizes, such as its connection tools, is read once.
      chat.workspace = @conversation.workspace if chat.workspace_id == @conversation.workspace_id
      # A turn paused on the person's confirmation is theirs, so a hand back waits for their next turn, which tells it.
      return nil if @handed_back && !setup_step(STEP_HAND_BACK_ROOM) { room_for_a_note?(chat) }

      setup_step(STEP_DISCARD) { chat.discard_interrupted_reply! }
      setup_step(STEP_CLOSE_CALLS) { withdraw(chat.close_unfinished_calls!) }
      setup_step(STEP_TAKE_QUEUED) { take_queued(chat) }
      setup_step(STEP_HELD_CALL) { run_held_call(chat) } if @held_call
      setup_step(STEP_PULL_REQUEST_FIX) { run_pull_request_fix(chat) } if @pull_request_fix
      setup_step(STEP_CODE_PAUSE) { run_code_pause(chat) } if @code_pause
      setup_step(STEP_PLAN_NOTE) { chat.nudge!(Conversation::Plans.note(@plan, @plan_move, @turn.asker)) if room_for_a_note?(chat) } if @plan
      setup_step(STEP_HAND_BACK_NOTE) { chat.nudge!(Conversation::Watches.hand_back_note(@handed_back)) if @handed_back.hand_back_noted! } if @handed_back
      # The turn before this one already answered what this job was queued for.
      if setup_step(STEP_ANSWERED_ALREADY) { answered_already?(chat) }
        setup_step(STEP_DELIVERED) { @conversation.reply_delivered! }
        return nil
      end

      # A question that waited behind the last turn was never marked as owed, since one already was.
      setup_step(STEP_EXPECT_REPLY) { @conversation.expect_reply! }
      # Pressed while this turn waited behind the last one.
      return setup_step(STEP_STOPPED) { stopped!(chat) } if setup_step(STEP_STOP_REQUESTED) { chat.stop_requested? }

      setup_step(STEP_THINKING) { thinking! }
      purse = setup_step(STEP_LISTENERS) do
        @turn.listen_to_progress { |key, update| report_progress(key, update) }
        chat.on_making_room { |compaction| delivery.made_room(compaction) }
        FirefightAi::AgentLoop::Purse.new
      end
      setup_step(STEP_HELD_OUTCOMES) { tell_held_outcomes(chat) }
      @changes = setup_step(STEP_CATCH_UP) { Chat::Tools::Changes.catch_up!(@turn, chat).then { |caught| caught if caught.note } }
      setup_step(STEP_SPECIALISTS) do
        @turn.asks_specialists = Chat::Specialists.ask?(@turn, picked_model || FirefightAi.model_for(AiPurpose::INVESTIGATION, workspace: @conversation.workspace))
      end
      presented = setup_step(STEP_PRESENTED) { Chat::Tools.presented(@turn, responder.ai_model) }
      suspects = setup_step(STEP_SUSPECTS) { tell_suspects(chat) }
      [ chat, purse, presented, suspects ]
    end

    tools, stable_context, turn_context, turn_budget, checks = timed_phase(PHASE_CONTEXT) do
      context = Conversation::Context.new(@conversation, @turn)
      [
        Conversation::Tools.for(@turn, offer: Chat::Tools.offer_to(chat), helpers: helper_share(chat, purse), presented: presented) +
          presented.loaded + Chat::Tools.known(@turn, chat),
        context.stable,
        context.current,
        budget,
        Conversation::Checks.new(chat, since: @marked, choice: Chat::Helpers.side_model(@conversation.workspace, main: helper_main_model),
                                       inferable: @conversation, member: member, facts: suspects).all
      ]
    end

    @turn.release_catalog!
    @conversation.workspace.release_reads!
    outcome = timed_phase(PHASE_RESPONDER) do |started|
      @responder_started = started
      responder.run(
        chat: chat,
        tools: tools,
        deferred_tools: presented.deferred,
        stable_context: stable_context,
        context: turn_context,
        budget: turn_budget,
        on_step: method(:report_step),
        on_progress: method(:report_tool_progress),
        on_chunk: shown_text.method(:add),
        nudge: chat.method(:nudge!),
        memory: chat,
        take_messages: -> { [ take_queued(chat), tell_changes(chat), tell_watch_corrections(chat) ].any? },
        canceled: chat.method(:stop_requested?),
        purse: purse,
        checks: checks,
        on_backup: ->(failed, backup, error) { switched_model(chat, failed, backup, error) },
        # A model the person picked is theirs to know about, so its account running dry is said too.
        on_take_over: (->(failed, following, error) { switched_model(chat, failed, following, error) } if picked_model)
      ) do |turn|
        record(turn)
      end
    end

    timed_phase(PHASE_AFTER) do
      shown_text.finish
      return stopped!(chat) if outcome.status == FirefightAi::AgentLoop::STATUS_CANCELED
      return ask_to_confirm(chat, outcome) if waiting?(outcome)

      @reply = reply_for(outcome, chat)
      # Cleared before the page is told, so its reload sees the turn as over.
      @conversation.reply_delivered!
      # A stop pressed as the answer finished has nothing left to stop, and must not stop the next question.
      chat.clear_stop!
      # Before the page is told, so the setup guide it reloads already says Halon answered.
      @conversation.workspace.onboarding&.halon_answered!(@conversation) if answered?(outcome)
      delivery.answered!(@reply, sources: (sources_of(chat) if answered?(outcome)) || [])
    end
    outcome
  rescue FirefightAi::Canceled
    stopped!(@conversation.chat_record)
  ensure
    @conversation.workspace.release_reads!
  end

  private

  def delivery = @delivery ||= Conversation::Delivery.for(@conversation, turn_started_at: @turn_started_at || Time.current)

  # Who a model call is ledgered under. A chat in an issue acts as Firefight's own agent, which is no member.
  def member = (@turn.asker unless @conversation.issue?)

  # The reply as it streams, without the line saying Halon's next step (FirefightAi::NextStep).
  def shown_text
    @shown_text ||= FirefightAi::NextStep::Stream.new do |text|
      first_text_shown
      delivery.chunk(text)
    end
  end

  # Where a reply's time goes, logged per phase and spanned when a tracer is set (config/initializers/opentelemetry.rb).
  def timed_phase(name)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    traced("conversation.reply.#{name}") { yield started }
  ensure
    Rails.logger.info({ event: PHASE_EVENT, phase: name, duration_ms: elapsed_ms(started), conversation_id: @conversation.id }.to_json)
  end

  # One step of setup, logged and spanned inside the setup phase's span with the queries it sent, since setup's time is
  # mostly round trips to the database.
  def setup_step(name, &)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    queries = Conversation::Runner::QueryCount.new
    traced("conversation.reply.#{PHASE_SETUP}.#{name}") { queries.count(&) }
  ensure
    Rails.logger.info({ event: SETUP_STEP_EVENT, step: name, duration_ms: elapsed_ms(started), db_ms: queries&.db_ms, queries: queries&.total, cached: queries&.cached,
                        conversation_id: @conversation.id }.to_json)
  end

  # A stop is the person pressing Stop, so its span ends as OK with no exception on it, which the SDK keeps over the error
  # in_span sets after. Any other failure is recorded here, since in_span is told not to.
  def traced(span_name)
    Firefight::TRACER.in_span(span_name, attributes: { "conversation.id" => @conversation.id }, record_exception: false) do |span|
      yield
    rescue FirefightAi::Canceled
      span.status = OpenTelemetry::Trace::Status.ok
      raise
    rescue StandardError => error
      span.record_exception(error)
      raise
    end
  end

  # The first text shown to the person, which on a turn that calls tools first comes after them, and on one that only
  # calls tools never comes.
  def first_text_shown
    return if @first_text_logged || !@responder_started

    @first_text_logged = true
    Rails.logger.info({ event: FIRST_TEXT_EVENT, duration_ms: elapsed_ms(@responder_started), conversation_id: @conversation.id }.to_json)
  end

  def elapsed_ms(started) = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

  def responder
    @responder ||= FirefightAi::Responder.new(
      @conversation.workspace, inferable: @conversation, member: member,
      output_style: delivery.output_style, model: picked_model, specialists: @turn.asks_specialists?
    )
  end

  def picked_model
    @picked_model = @conversation.picked_model_choice unless defined?(@picked_model)
    @picked_model
  end

  # A model the person picked answers them. The checks Halon hands to helpers keep the workspace's models.
  def helper_main_model = @helper_main_model ||= picked_model ? @conversation.workspace_model : responder.ai_model

  # Saved too, so an unanswered turn is not silence on the next visit.
  def reply_for(outcome, chat)
    return chat.messages.reload.last&.content.presence || NO_ROOM_LEFT if answered?(outcome)

    @conversation.note!(NO_ROOM_LEFT)
    NO_ROOM_LEFT
  end

  # A confirmation the person moved past is redrawn where it was asked, so its buttons are gone.
  def withdraw(closed)
    withdrawn = closed.select { |call| call.approval == Chat::APPROVAL_WITHDRAWN }
    return if withdrawn.empty?

    delivery.withdrawn!(withdrawn)
    Conversation::OwnerAsks.withdraw!(@conversation.chat, withdrawn.map(&:tool_call_id))
  end

  def answered?(outcome) = outcome.status == FirefightAi::AgentLoop::STATUS_ANSWERED

  # What changed around what is failing, before the first model call of a turn that troubleshoots (Conversation::Suspects),
  # as a note Halon reads as candidates. Returned too, for the challenger to read beside what the turn read.
  def tell_suspects(chat)
    return nil unless room_for_a_note?(chat)

    words = chat.messages.where(role: Chat::Message::ROLE_USER, nudge: false).reorder(created_at: :desc).first&.content
    note = Conversation::Suspects.note(@turn, words)
    chat.nudge!(note) if note
    note
  end

  # What the turn read, from its own calls, for the line under the reply.
  def sources_of(chat)
    reply = chat.messages.where(role: Chat::Message::ROLE_ASSISTANT).reorder(created_at: :desc, id: :desc).first
    reply&.chat = chat
    reply ? Chat::Sources.for_reply(reply) : []
  end

  # The person stopped this answer. What ran stays in the chat, and the next question starts clean.
  def stopped!(chat)
    chat.clear_stop!
    chat.discard_interrupted_reply!
    chat.answer_stopped_calls!(STOPPED_BEFORE_RUNNING, ran: running.to_a, ran_text: STOPPED_WHILE_RUNNING)
    @conversation.note!(STOPPED)
    @reply = STOPPED
    @conversation.reply_delivered!
    delivery.answered!(STOPPED)
    FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_CANCELED, turns_used: 0, spent_micros: 0)
  end

  # The call runs once, as whoever it was approved for, and Halon reads what it answered before it says how it went. The
  # thread shows Halon working while it runs, and a code change's progress reaches the call's own message as it moves.
  def run_held_call(chat)
    return unless @held_call.status == Chat::HeldCall::STATUS_RUNNING

    thinking!
    said = Conversation::HeldCalls.execute!(@held_call, progress: held_call_progress(chat))
    return unless room_for_a_note?(chat)

    chat.nudge!(Conversation::HeldCalls.ran_note(@held_call.reload, said))
    @held_call.update_columns(told_at: Time.current)
  end

  # Kept with the chat by the call's id, as a step's work is, and shown on the call's message no more often than the
  # platform allows, so the message reads as a live checklist. A report that cannot be kept or shown never stops the call.
  def held_call_progress(chat)
    shown_pace = Chat::CodeFixProgress::Pace.new(every: WorkspaceAdapter.for(@conversation.workspace).agent_step_update_interval)
    lambda do |update|
      next unless update.is_a?(Chat::CodeFixProgress)

      shown = shown_pace.due?(@held_call.tool_call_id, update)
      Chat::StepProgress.keep!(chat, @held_call.tool_call_id, update) if saving_pace.due?(@held_call.tool_call_id, update) || shown
      Conversation::HeldCalls.moved!(@held_call, progress: update) if shown
    rescue StandardError => error
      Rails.logger.warn({ event: "held_call.progress_not_shown", held_call_id: @held_call.id, error: error.class.name }.to_json)
    end
  end

  # Held calls that ended since Halon last looked, so it never says one is still waiting, or that one ran when it did not.
  # What its watches said since, so it never repeats a milestone or says one is still going after it ended. And that a
  # result the last turn read saying something could not be used may be out of date, so a refusal is checked again.
  def tell_held_outcomes(chat)
    return unless room_for_a_note?(chat)

    note = Conversation::HeldCalls.untold_note(chat)
    chat.nudge!(note) if note
    watched = Conversation::Watches.untold_note(chat)
    chat.nudge!(watched) if watched
    mitigated = Conversation::Mitigations.untold_note(chat)
    chat.nudge!(mitigated) if mitigated
    noticed = PullRequestFollowing.untold_note(@conversation)
    chat.nudge!(noticed) if noticed
    stale = Chat::StaleRefusals.note(chat)
    chat.nudge!(stale) if stale
    decided = Chat::HandbookProposal.untold_for!(@conversation).map(&:outcome_note) + Chat::CustomSkill::Version.untold_for!(@conversation).map(&:outcome_note)
    chat.nudge!(decided.join("\n")) if decided.any?
    Chat::Watch::Step.hand_back_untold(chat).each do |step|
      chat.nudge!(Conversation::Watches.hand_back_note(step)) if step.hand_back_noted!
    end
  end

  # The person said yes with Fix it, so the code change runs before Halon answers, and Halon reads what it said.
  def run_pull_request_fix(chat)
    said = PullRequestFollowing.run_fix!(@turn, @pull_request_fix)
    chat.nudge!(PullRequestFollowing.fixed_note(@pull_request_fix, said)) if room_for_a_note?(chat)
  end

  # The person pressed Continue, so the paused change carries on before Halon answers, and Halon reads what it said. It
  # runs as a step of this turn, saved before it starts, so the page shows it working with the change's progress from
  # the first moment and again after a reload. A chat waiting on a call takes nothing between the call and its result,
  # so there the change carries on outside a step.
  def run_code_pause(chat)
    tool = CodeAgentPauseService.continue_tool(@code_pause)
    return run_code_pause_outside_a_step(chat) unless tool && room_for_a_note?(chat)

    thinking!
    @turn.listen_to_progress { |key, update| report_progress(key, update) }
    chat.nudge!(CodeAgentPauseService.continuing_note(@code_pause))
    arguments = CodeAgentPauseService.continue_arguments(@code_pause)
    call = chat.messages.create!(role: Chat::Message::ROLE_ASSISTANT, content: "")
               .ruby_llm_tool_calls.create!(tool_call_id: "call_#{SecureRandom.hex(12)}", name: tool.model_facing_name, arguments: arguments)
    report_step(FirefightAi::AgentLoop::Step.new(key: call.tool_call_id, tool: call.name, status: FirefightAi::AgentLoop::STEP_RUNNING, arguments: arguments))
    said = CodeAgentPauseService.run_continue!(@turn, @code_pause, tool_call_id: call.tool_call_id)
    chat.add_message(role: Chat::Message::ROLE_TOOL, content: said, tool_call_id: call.tool_call_id)
    report_step(FirefightAi::AgentLoop::Step.new(key: call.tool_call_id, tool: nil, status: FirefightAi::AgentLoop::STEP_DONE))
  end

  # A turn that carried a paused change on started its answer already, which a chat platform shows once.
  def thinking!
    return if @thinking

    @thinking = true
    delivery.thinking!
  end

  def run_code_pause_outside_a_step(chat)
    said = CodeAgentPauseService.run_continue!(@turn, @code_pause)
    chat.nudge!(CodeAgentPauseService.continued_note(@code_pause, said)) if room_for_a_note?(chat)
  end

  # A provider refuses anything between a call and its result, so nothing is said while a call waits for the person.
  def room_for_a_note?(chat) = chat.calls_in_play.where(result_id: nil).none?

  # Only the asker's own messages, since the turn acts with their permissions. A chat in an issue acts as its agent
  # whoever wrote there, so it takes every follow up.
  def take_queued(chat)
    return chat.take_queued!.any? if @conversation.issue?

    asker = @turn.asker
    asker.is_a?(WorkspaceMembership) && chat.take_queued!(from: asker).any?
  end

  # A connection changed since the chat last looked, at the start of the turn or while it works. The agent is told before
  # its next model call, and a newly switched on tool of a group it opened is handed to it.
  def tell_changes(chat)
    caught = @changes || Chat::Tools::Changes.catch_up!(@turn, chat)
    @changes = nil
    return false unless caught.note

    Chat::Tools.offer_to(chat).call(caught.offered) if caught.offered.any?
    chat.nudge!(caught.note)
    true
  end

  # A reading this turn took disagreed with what a watch had, so Halon is told before its next model call, the one place
  # a note keeps the chat valid.
  def tell_watch_corrections(chat)
    notes = watch_notes.slice!(0..)
    return false if notes.empty?

    chat.nudge!(notes.join("\n"))
    true
  end

  def watch_notes = @watch_notes ||= []

  # Fresh beats remembered. A call this turn made with the very read a watch in this chat makes is handed to the watch.
  # A watch's reads only read, so a call that matches one read too.
  def hand_reading_to_watches(key, answered)
    tool, arguments = asked.delete(key)
    return unless tool && Chat::Watch.active.exists?(chat_id: @conversation.chat.id)

    text = answered.call&.result&.content
    return if text.blank?

    note = Conversation::Watches.observe!(@conversation.chat, tool, arguments, FirefightAi::Evidence.unframe(text).body)
    watch_notes << note if note
  rescue StandardError => error
    Rails.logger.warn({ event: "conversation.watch_reading_not_taken", conversation_id: @conversation.id, error: error.class.name }.to_json)
  end

  def asked = @asked ||= {}

  # The last word is a finished reply, so nothing is waiting for one. A turn paused on a confirmation ends on a tool call.
  def answered_already?(chat)
    chat.sent_messages.reload
    last = chat.last_word
    last.present? && last.role == Chat::Message::ROLE_ASSISTANT && !last.nudge && last.ruby_llm_tool_calls.empty?
  end

  def waiting?(outcome) = outcome.status == FirefightAi::AgentLoop::STATUS_WAITING

  # The turn stops on calls that need the person's decision, and they are asked rather than answered.
  def ask_to_confirm(chat, outcome)
    chat.request_decisions!(chat.to_llm.pending_approvals.map(&:id))
    Chat::Tools.settle_asked!(@turn, chat.awaiting_decision.to_a)
    Chat::Tools::Target.record!(@turn, chat.awaiting_decision.where(target: nil).to_a)
    Chat::Tools::Provenance.record!(@turn, chat.awaiting_decision.where(provenance: nil).to_a)
    Chat::Safeguards.prepare!(@turn, chat.awaiting_decision.to_a)
    @conversation.reply_delivered!
    chat.clear_stop!
    delivery.confirm!(chat.awaiting_decision.to_a)
    outcome
  end

  def switched_model(chat, failed, backup, error)
    delivery.switched_model(Chat::ModelSwitch.record!(chat, failed: failed, backup: backup, error: error))
  end

  # The finished report only has the key, so the step is remembered from when it started.
  def report_step(step)
    if step.tool.present?
      seen[step.key] = Chat::Tools.step(step.tool, step.arguments, workspace: @conversation.workspace)
      kinds[step.key] = Chat::Tools.kind(step.tool, @conversation.workspace, step.arguments)
      asked[step.key] = [ step.tool, step.arguments ]
    end
    done = step.status == FirefightAi::AgentLoop::STEP_DONE
    done ? running.delete(step.key) : running.add(step.key)
    # A finished call is read once, for the watches and for what it got back.
    answered = Answered.new(@conversation.chat, step.key) if done
    hand_reading_to_watches(step.key, answered) if done
    shown = seen[step.key]
    return unless shown

    shown = shown.with(card: Chat::Tools.chart_card) if done && shown.card.nil? && charted?(step.key)
    delivery.step(
      key: step.key, step: shown, status: step.status, kind: kinds[step.key],
      seconds: done ? seconds_since_last_step : 0, outcome: (Chat::StepOutcome.for_call(answered.call, @conversation.chat) if done), progress: works[step.key]
    )
  end

  # A finished call with its answer, read the first time something asks for it. The wrapper marked the call as the tool
  # answered, and its answer is saved, before the loop reports the step done.
  class Answered
    def initialize(chat, key)
      @chat = chat
      @key = key
    end

    def call = defined?(@call) ? @call : (@call = @chat.outcome_call(@key))
  end

  # Kept with the chat this often at most while a coding agent works, and always once it ends.
  PROGRESS_SAVED_EVERY = 2

  # A coding agent writing a change says how it is going as it works. Its steps are kept with the chat and shown under
  # the step. A sentence from any other tool is not shown in a chat, as before, and a report that cannot be kept or
  # shown never stops the call.
  def report_progress(key, update)
    shown = seen[key]
    return unless update.is_a?(Chat::CodeFixProgress) && shown

    works[key] = update
    Chat::StepProgress.keep!(@conversation.chat, key, update, since: @turn_started_at || Time.current) if saving_pace.due?(key, update)
    delivery.progress(key: key, step: shown, kind: kinds[key], progress: update)
  rescue StandardError => error
    Rails.logger.warn({ event: "conversation.progress_not_kept", conversation_id: @conversation.id, error: error.class.name }.to_json)
  end

  def saving_pace = @saving_pace ||= Chat::CodeFixProgress::Pace.new(every: PROGRESS_SAVED_EVERY)

  # Any other long tool says how far it got through RubyLLM's progress, such as helpers reporting or a command running,
  # which the dashboard shows under its step while it runs. It may report from a thread it started, so one report goes
  # out at a time, and one that cannot be shown never stops the call. A coding agent's own work is shown as above.
  def report_tool_progress(progress)
    shown = seen[progress.key]
    activity = Chat::ToolActivity.from(progress)
    return if shown.nil? || activity.empty? || works.key?(progress.key)

    @progress_lock.synchronize { delivery.activity(key: progress.key, step: shown, kind: kinds[progress.key], activity: activity) }
  rescue StandardError => error
    Rails.logger.warn({ event: "conversation.tool_progress_not_shown", conversation_id: @conversation.id, error: error.class.name }.to_json)
  end

  def works = @works ||= {}

  # The wrapper kept the call's charts as the tool answered, before the loop reports the step done.
  def charted?(key) = @conversation.chat.charts.drawn_by(key, since: @turn_started_at || Time.current).exists?

  # Counted from the end of the last step, so the model's own time between calls counts as thinking.
  def seconds_since_last_step
    now = Time.current
    since = now - (@marked || now)
    @marked = now
    since.round
  end

  def seen = @seen ||= {}

  # The calls that started and have not answered, which a stop ends while they run.
  def running = @running ||= Set.new

  def kinds = @kinds ||= {}

  # The loop counts from the start of this question, so the conversation is given what each turn added.
  def record(turn)
    @conversation.add_turn!(
      turns: turn.turns_used - counted.turns_used, spent_micros: turn.spent_micros - counted.spent_micros
    )
    @counted = turn
  end

  def counted = @counted ||= FirefightAi::AgentLoop::Turn.new(turns_used: 0, spent_micros: 0)

  # What this question lends the helpers Halon hands checks to: its purse and cap, its stop, and the person it acts for,
  # whom each helper reads as on a copy of the turn of its own.
  # Where this turn asks specialists, they read with what it may reach.
  def helper_share(chat, purse)
    conversation = @conversation
    asker = @turn.asker
    Chat::Helpers::Share.new(
      purse: purse, max_spend_cents: conversation.max_spend_cents, since: @marked, canceled: chat.method(:stop_requested?),
      moved: Chat::Helpers.teller(delivery, chat),
      fresh_parent: -> { Conversation::Turn.new(Conversation.find(conversation.id), asker: asker&.class&.find(asker.id), reads_only: true) },
      choose: ->(deep) { deep ? helper_main_model : Chat::Helpers.side_model(conversation.workspace, main: helper_main_model) },
      inferable: conversation, member: member,
      specialists: (Chat::Specialists::Live.new(@turn) if Chat::Specialists.for?(@turn))
    )
  end

  # A question gets its own budget, so a long chat does not run dry for good. What every question
  # spent still adds up on the conversation.
  def budget
    FirefightAi::AgentLoop::Budget.new(
      max_spend_cents: @conversation.max_spend_cents, max_turns: @conversation.max_turns
    )
  end
end
