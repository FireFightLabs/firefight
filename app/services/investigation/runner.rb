# The app half of a run: the chat, the tools, and what each turn spent.
class Investigation::Runner
  # Another worker holds the run.
  class LeaseLost < StandardError; end

  Result = Data.define(:status, :error_summary)

  # Why the loop stopped, in the plain words the model keeps.
  STOP_REASONS = {
    FirefightAi::AgentLoop::STATUS_CANCELED => Investigation::STOPPED_BY_A_RESPONDER,
    FirefightAi::AgentLoop::STATUS_OUT_OF_BUDGET => Investigation::BUDGET_SPENT,
    FirefightAi::AgentLoop::STATUS_OUT_OF_TURNS => Investigation::TOO_MANY_TURNS,
    FirefightAi::AgentLoop::STATUS_STALLED => Investigation::STALLED,
    FirefightAi::AgentLoop::STATUS_REPEATED_TOOL_CALL => Investigation::REPEATED_CALL
  }.freeze

  def initialize(investigation)
    @investigation = investigation
  end

  def run
    delivery.start!
    chat = @investigation.chat_record(investigator.ai_model)
    chat.discard_interrupted_reply!
    chat.close_unfinished_calls!
    @investigation.close_interrupted_steps!
    @changes = Chat::Tools::Changes.catch_up!(@investigation, chat).then { |caught| caught if caught.note }
    purse = FirefightAi::AgentLoop::Purse.new(@investigation.spent_micros)

    outcome = investigator.run(
      chat: chat,
      tools: Investigation::Tools.for(@investigation, offer: Chat::Tools.offer_to(chat), helpers: helper_share(purse)) +
             Chat::Tools.known(@investigation, chat),
      seed_pack: @investigation.starting_facts,
      budget: budget,
      answered: -> { @investigation.reload.finding.present? },
      canceled: -> { @investigation.reload.cancel_requested? },
      on_step: method(:report_step),
      nudge: chat.method(:nudge!),
      memory: chat,
      take_messages: method(:take_notes),
      purse: purse
    ) do |turn|
      unless @investigation.record_turn!(turns_used: turn.turns_used, spent_micros: turn.spent_micros)
        raise LeaseLost, "another worker holds this run"
      end
    end

    deliver(result_for(outcome))
  rescue FirefightAi::Canceled
    deliver(Result.new(status: Investigation::STATUS_CANCELED, error_summary: Investigation::STOPPED_BY_A_RESPONDER))
  end

  private

  def delivery = @delivery ||= (@investigation.rehearsal? ? Investigation::QuietDelivery : Investigation::Delivery).new(@investigation)

  def deliver(result)
    if @investigation.reload.finding
      delivery.answered!(@investigation.finding)
    else
      delivery.stopped!(result.error_summary)
    end
    result
  end

  # A finished step says how it went, read from the call the run's chat kept, since the wrapper marked it as it answered.
  def report_step(step)
    titles[step.key] = Chat::Tools.step(step.tool, step.arguments, workspace: @investigation.workspace)&.title if step.tool.present?
    title = titles[step.key]
    return unless title

    done = step.status == FirefightAi::AgentLoop::STEP_DONE
    delivery.step(key: step.key, title: title, status: step.status, outcome: (outcome_of(step.key) if done))
  end

  def outcome_of(key)
    chat = @investigation.chat
    Chat::StepOutcome.for_call(chat.outcome_call(key), chat) if chat
  end

  def titles = @titles ||= {}

  # Shown where the run's steps are, so whoever added a note sees the run read it. A starting memory a person set aside
  # since the run began is told to the agent as a note of its own, which nobody needs to see.
  def take_notes
    added = @investigation.take_notes!.each do |note|
      name = note.sender&.display_name || Investigation::Noting::UNNAMED_RESPONDER
      delivery.step(key: "note-#{note.id}", title: "Read what #{name} added", status: FirefightAi::AgentLoop::STEP_DONE)
    end.any?
    changed = @investigation.untold_memory_changes!
    @investigation.chat.nudge!(changed.join("\n")) if changed.any?
    connections = tell_changes
    added || changed.any? || connections
  end

  # A connection changed since the run last looked, at its start or while it works. The agent is told before its next
  # model call, and a newly switched on tool of a group it opened is handed to it.
  def tell_changes
    chat = @investigation.chat
    caught = @changes || Chat::Tools::Changes.catch_up!(@investigation, chat)
    @changes = nil
    return false unless caught.note

    Chat::Tools.offer_to(chat).call(caught.offered) if caught.offered.any?
    chat.nudge!(caught.note)
    true
  end

  def investigator
    @investigator ||= FirefightAi::Investigator.new(
      @investigation.workspace, inferable: @investigation, member: member, model: @investigation.ai_model
    )
  end

  # Inference rows name a person only when a person asked.
  def member
    @investigation.triggered_by if @investigation.triggered_by.is_a?(WorkspaceMembership)
  end

  # What the run lends the helpers it hands checks to. Each reads as the investigator on a copy of the run of its own, so
  # every read is a numbered step the answer can cite. Nobody watches a run's chat live, so nothing is told as they move.
  def helper_share(purse)
    id = @investigation.id
    Chat::Helpers::Share.new(
      purse: purse, max_spend_cents: @investigation.max_spend_cents, since: @investigation.created_at,
      canceled: -> { Investigation.where(id: id).pick(:cancel_requested) == true }, moved: Chat::Helpers.teller(delivery, @investigation.chat),
      fresh_parent: -> { Investigation.find(id) }, choose: ->(deep) { deep ? investigator.ai_model : helper_side_model },
      inferable: @investigation, member: member
    )
  end

  # A rehearsal measures Halon on the deployment's account, and one comparing models runs every check on the model it compares.
  def helper_side_model
    return investigator.ai_model if @investigation.model_choice
    return Chat::Helpers.side_model(@investigation.workspace, main: investigator.ai_model, deployment: true) if @investigation.rehearsal?

    Chat::Helpers.side_model(@investigation.workspace, main: investigator.ai_model)
  end

  def budget
    FirefightAi::AgentLoop::Budget.new(
      max_spend_cents: @investigation.max_spend_cents, max_turns: @investigation.max_turns,
      turns_used: @investigation.turns_used, spent_micros: @investigation.spent_micros
    )
  end

  # An answer is the only success.
  def result_for(outcome)
    return Result.new(status: Investigation::STATUS_SUCCEEDED, error_summary: nil) if @investigation.reload.finding
    if outcome.status == FirefightAi::AgentLoop::STATUS_CANCELED
      return Result.new(status: Investigation::STATUS_CANCELED, error_summary: Investigation::STOPPED_BY_A_RESPONDER)
    end

    Result.new(status: Investigation::STATUS_FAILED, error_summary: reason_for(outcome.status))
  end

  def reason_for(status) = STOP_REASONS.fetch(status, Investigation::ENDED_WITHOUT_AN_ANSWER)
end
