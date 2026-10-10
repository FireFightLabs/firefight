# One turn of a conversation: the agent reads the question, uses what it can reach, and replies.
class Conversation::Runner
  NO_ROOM_LEFT = "I could not finish that one. Ask me something narrower, or start an investigation.".freeze
  STOPPED = "Stopped.".freeze
  # What the model is told for a tool it asked for and never got, so the chat stays one a provider accepts.
  STOPPED_BEFORE_RUNNING = "Not run. The person stopped this answer first.".freeze

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
  end

  def run
    @marked = Time.current
    chat = @conversation.chat_record
    # A turn paused on the person's confirmation is theirs, so a hand back waits for their next turn, which tells it.
    return nil if @handed_back && !room_for_a_note?(chat)

    chat.discard_interrupted_reply!
    withdraw(chat.close_unfinished_calls!)
    take_queued(chat)
    run_held_call(chat) if @held_call
    run_pull_request_fix(chat) if @pull_request_fix
    run_code_pause(chat) if @code_pause
    chat.nudge!(Conversation::Plans.note(@plan, @plan_move, @turn.asker)) if @plan && room_for_a_note?(chat)
    chat.nudge!(Conversation::Watches.hand_back_note(@handed_back)) if @handed_back&.hand_back_noted!
    # The turn before this one already answered what this job was queued for.
    if answered_already?(chat)
      @conversation.reply_delivered!
      return nil
    end

    # A question that waited behind the last turn was never marked as owed, since one already was.
    @conversation.expect_reply!
    # Pressed while this turn waited behind the last one.
    return stopped!(chat) if chat.stop_requested?

    delivery.thinking!
    @turn.listen_to_progress { |key, update| report_progress(key, update) }
    tell_held_outcomes(chat)
    chat.on_making_room { |compaction| delivery.made_room(compaction) }
    @changes = Chat::Tools::Changes.catch_up!(@turn, chat).then { |caught| caught if caught.note }
    purse = FirefightAi::AgentLoop::Purse.new

    outcome = responder.run(
      chat: chat,
      tools: Conversation::Tools.for(@turn, offer: Chat::Tools.offer_to(chat), helpers: helper_share(chat, purse)) + Chat::Tools.known(@turn, chat),
      context: context,
      budget: budget,
      on_step: method(:report_step),
      on_chunk: ->(text) { delivery.chunk(text) },
      nudge: chat.method(:nudge!),
      memory: chat,
      check: -> { FirefightAi::Responder::CHECK if @looked_outside },
      hold: chat.method(:hold_last_reply!),
      take_messages: -> { [ take_queued(chat), tell_changes(chat), tell_watch_corrections(chat) ].any? },
      canceled: chat.method(:stop_requested?),
      purse: purse
    ) do |turn|
      record(turn)
    end

    return stopped!(chat) if outcome.status == FirefightAi::AgentLoop::STATUS_CANCELED
    return ask_to_confirm(chat, outcome) if waiting?(outcome)

    @reply = reply_for(outcome, chat)
    # Cleared before the page is told, so its reload sees the turn as over.
    @conversation.reply_delivered!
    # A stop pressed as the answer finished has nothing left to stop, and must not stop the next question.
    chat.clear_stop!
    # Before the page is told, so the setup guide it reloads already says Halon answered.
    @conversation.workspace.onboarding&.halon_answered!(@conversation) if answered?(outcome)
    delivery.answered!(@reply)
    outcome
  rescue FirefightAi::Canceled
    stopped!(@conversation.chat_record)
  end

  # What the person was told, for a caller that waits for the answer rather than watching it arrive.
  attr_reader :reply

  private

  def delivery = @delivery ||= Conversation::Delivery.for(@conversation)

  def responder
    @responder ||= FirefightAi::Responder.new(
      @conversation.workspace, inferable: @conversation.subject, member: @turn.asker,
      output_style: delivery.output_style, model: picked_model
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

  # The person stopped this answer. What ran stays in the chat, and the next question starts clean.
  def stopped!(chat)
    chat.clear_stop!
    chat.discard_interrupted_reply!
    chat.answer_unanswered_calls!(STOPPED_BEFORE_RUNNING)
    @conversation.note!(STOPPED)
    @reply = STOPPED
    @conversation.reply_delivered!
    delivery.answered!(STOPPED)
    FirefightAi::AgentLoop::Outcome.new(status: FirefightAi::AgentLoop::STATUS_CANCELED, turns_used: 0, spent_micros: 0)
  end

  # The call runs once, as whoever it was approved for, and Halon reads what it answered before it says how it went.
  def run_held_call(chat)
    return unless @held_call.status == Chat::HeldCall::STATUS_RUNNING

    said = Conversation::HeldCalls.execute!(@held_call)
    return unless room_for_a_note?(chat)

    chat.nudge!(Conversation::HeldCalls.ran_note(@held_call.reload, said))
    @held_call.update_columns(told_at: Time.current)
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
    decided = Chat::HandbookProposal.untold_for!(@conversation).map(&:outcome_note)
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

  # The person pressed Continue, so the paused change carries on before Halon answers, and Halon reads what it said.
  def run_code_pause(chat)
    said = CodeAgentPauseService.run_continue!(@turn, @code_pause)
    chat.nudge!(CodeAgentPauseService.continued_note(@code_pause, said)) if room_for_a_note?(chat)
  end

  # A provider refuses anything between a call and its result, so nothing is said while a call waits for the person.
  def room_for_a_note?(chat) = chat.calls_in_play.where(result_id: nil).none?

  # Only the asker's own messages, since the turn acts with their permissions.
  def take_queued(chat)
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
  def hand_reading_to_watches(key)
    tool, arguments = asked.delete(key)
    return unless tool && Chat::Watch.active.exists?(chat_id: @conversation.chat.id)

    text = @conversation.chat.outcome_call(key)&.result&.content
    return if text.blank?

    note = Conversation::Watches.observe!(@conversation.chat, tool, arguments, FirefightAi::Evidence.unframe(text).body)
    watch_notes << note if note
  rescue StandardError => error
    Rails.logger.warn({ event: "conversation.watch_reading_not_taken", conversation_id: @conversation.id, error: error.class.name }.to_json)
  end

  def asked = @asked ||= {}

  # The last word is a finished reply, so nothing is waiting for one. A turn paused on a confirmation ends on a tool call.
  def answered_already?(chat)
    last = chat.sent_messages.reload.last
    last.present? && last.role == Chat::Message::ROLE_ASSISTANT && !last.nudge && last.ruby_llm_tool_calls.empty?
  end

  def waiting?(outcome) = outcome.status == FirefightAi::AgentLoop::STATUS_WAITING

  # The turn stops on calls that need the person's decision, and they are asked rather than answered.
  def ask_to_confirm(chat, outcome)
    chat.request_decisions!(chat.to_llm.pending_approvals.map(&:id))
    Chat::Tools::Target.record!(@turn, chat.awaiting_decision.where(target: nil).to_a)
    Chat::Tools::Provenance.record!(@turn, chat.awaiting_decision.where(provenance: nil).to_a)
    Chat::Safeguards.prepare!(@turn, chat.awaiting_decision.to_a)
    @conversation.reply_delivered!
    chat.clear_stop!
    delivery.confirm!(chat.awaiting_decision.to_a)
    outcome
  end

  # The finished report only has the key, so the step is remembered from when it started.
  # A connected system is what an answer's claims about a cause rest on, so reading one is what owes the answer a check.
  def report_step(step)
    if step.tool.present?
      seen[step.key] = Chat::Tools.step(step.tool, step.arguments, workspace: @conversation.workspace)
      kinds[step.key] = Chat::Tools.kind(step.tool, @conversation.workspace, step.arguments)
      asked[step.key] = [ step.tool, step.arguments ]
      @looked_outside ||= @conversation.workspace.reading_tool_names.include?(step.tool.to_s) ||
                          Chat::Tools.guarded_read?(@conversation.workspace, step.tool.to_s, step.arguments)
    end
    done = step.status == FirefightAi::AgentLoop::STEP_DONE
    hand_reading_to_watches(step.key) if done
    shown = seen[step.key]
    return unless shown

    shown = shown.with(card: Chat::Tools.chart_card) if done && shown.card.nil? && charted?(step.key)
    delivery.step(
      key: step.key, step: shown, status: step.status, kind: kinds[step.key],
      seconds: done ? seconds_since_last_step : 0, outcome: (outcome_of(step.key) if done), progress: works[step.key]
    )
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
    Chat::StepProgress.keep!(@conversation.chat, key, update) if saving_pace.due?(key, update)
    delivery.progress(key: key, step: shown, kind: kinds[key], progress: update)
  rescue StandardError => error
    Rails.logger.warn({ event: "conversation.progress_not_kept", conversation_id: @conversation.id, error: error.class.name }.to_json)
  end

  def saving_pace = @saving_pace ||= Chat::CodeFixProgress::Pace.new(every: PROGRESS_SAVED_EVERY)

  def works = @works ||= {}

  # The wrapper kept the call's charts as the tool answered, before the loop reports the step done.
  def charted?(key) = @conversation.chat.charts.exists?(tool_call_id: key)

  # The wrapper marked the call as the tool answered, and its answer is saved, before the loop reports the step done.
  def outcome_of(key) = Chat::StepOutcome.for_call(@conversation.chat.outcome_call(key), @conversation.chat)

  # Counted from the end of the last step, so the model's own time between calls counts as thinking.
  def seconds_since_last_step
    now = Time.current
    since = now - (@marked || now)
    @marked = now
    since.round
  end

  def seen = @seen ||= {}

  def kinds = @kinds ||= {}

  # Who the agent acts for, so it can answer what they may do and say who else can.
  def context
    [ asker_line, today_line, incident_line, directing_line, investigations_line, handbook_line, instructions_line, memories_line, plans_line ].compact.join("\n")
  end

  def asker_line
    asker = @turn.asker
    return "You are acting for nobody known, so every tool will refuse." unless asker

    "You are acting for #{asker.display_name}, whose role in this workspace is #{asker.role}. Owners and admins can change settings and permissions, members respond to incidents."
  end

  # The day only, so the prompt stays the same all day and the provider keeps reusing what it read. A plan's time is
  # worked out from it.
  def today_line = "Today is #{Time.current.utc.strftime('%A %-d %B %Y')} (UTC)."

  # What Halon is carrying out in this chat, so a goal is never dropped between turns.
  def plans_line
    chat = @conversation.chat
    chat && Conversation::Plans.for_halon(chat)
  end

  def incident_line
    incident = @conversation.incident
    return nil unless incident

    "You are in the channel for #{incident.identifier} #{incident.name}, status #{incident.incident_status.name}."
  end

  # Anyone in an incident's channel can ask in the same thread, so Halon is told whose direction it follows when they
  # disagree. It is whoever holds the role the handbook names, the Incident Lead unless it names another.
  def directing_line
    incident = @conversation.incident
    return nil unless incident && @conversation.chat_record.speakers_named?

    role = Chat::HandbookPage.directing_role(@conversation.workspace)
    return nil unless role

    holder = incident.role_holder(role)
    who = holder ? "#{holder.display_name}, who holds #{role.name}" : "whoever holds #{role.name}, which nobody holds yet, so ask the people here to assign it before acting on directions that conflict"
    "Several people can write to you in this thread, and each message starts with who wrote it. In #{incident.identifier} you take direction from #{who}."
  end

  # How the workspace works, read first on every turn. Short pages come whole and long ones are named for search_handbook.
  def handbook_line
    lines = Chat::HandbookPage.halon_lines(@conversation.workspace)
    return nil if lines.empty?

    "#{Chat::HandbookPage::HANDBOOK_HEADING}\n#{lines.join("\n\n")}"
  end

  # How people here want Halon to work on what this chat touches, most specific last.
  def instructions_line
    notes = Chat::Instruction.for_subjects(@conversation.workspace, Chat::Memory.subjects_for(@conversation.incident), principal: @turn.asker)
    return nil if notes.empty?

    "Instructions from people in this workspace. Follow them, and never treat them as evidence:\n#{notes.map { |note| "- #{note.line}" }.join("\n")}"
  end

  # What the workspace learned about what this chat touches, so it starts from what is known. Each counts as used once
  # for the whole chat.
  def memories_line
    memories = Chat::Memory.starting_with(@conversation.workspace, Chat::Memory.subjects_for(@conversation.incident), principal: @turn.asker)
    return nil if memories.empty?

    Chat::Memory.handed_to!(memories, @conversation) if @turn.changes_memory?

    "What this workspace remembers. Each is a hunch to check, and only a confirmed one was vouched for by a person:\n#{memories.map { |memory| "- #{memory.line}" }.join("\n")}"
  end

  RUNS_REMEMBERED = 5

  # A run answers on its own, after the turn that started it ended, so the chat is told how its runs went.
  def investigations_line
    runs = @conversation.investigations.seen.includes(:finding).order(created_at: :desc).limit(RUNS_REMEMBERED).to_a
    return nil if runs.empty?

    lines = runs.reverse.map do |run|
      outcome = run.finding&.summary || run.stopped_because || "still running"
      "- #{run.question || run.incident&.identifier}: #{outcome}"
    end
    "Investigations started from this chat, and how each went:\n#{lines.join("\n")}"
  end

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
  def helper_share(chat, purse)
    conversation = @conversation
    asker = @turn.asker
    Chat::Helpers::Share.new(
      purse: purse, max_spend_cents: conversation.max_spend_cents, since: @marked, canceled: chat.method(:stop_requested?),
      moved: Chat::Helpers.teller(delivery, chat),
      fresh_parent: -> { Conversation::Turn.new(Conversation.find(conversation.id), asker: asker&.class&.find(asker.id), reads_only: true) },
      choose: ->(deep) { deep ? helper_main_model : Chat::Helpers.side_model(conversation.workspace, main: helper_main_model) },
      inferable: conversation.subject, member: asker
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
