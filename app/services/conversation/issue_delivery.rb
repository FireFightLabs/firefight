# What Halon says while it answers in a tracker's issue, as activities in the session someone opened there by assigning
# the issue to Firefight's app or mentioning it (Integrations::AgentSessions). Each tool is an action, shown while it
# runs and kept once it answered with how it went, and the answer is the response. The issue has no buttons, so what
# needs a person (a call to confirm, one waiting for approval) is said with a link to the chat in Firefight, where it is
# decided. A failure to say something is logged and never retried, since the answer is saved in the chat.
class Conversation::IssueDelivery
  OUTCOME_WORDS = {
    Chat::StepOutcome::KIND_ANSWERED => "Done", Chat::StepOutcome::KIND_FAILED => "Failed",
    Chat::StepOutcome::KIND_NOT_FOUND => "Not found", Chat::StepOutcome::KIND_REFUSED => "Not allowed"
  }.freeze
  SOURCES_SHOWN = 8

  def initialize(conversation)
    @conversation = conversation
    @since = Time.current
  end

  # The tracker reads Markdown, so the answer is written as it is for the dashboard.
  def output_style = nil

  # The session was told Halon is on it when it was opened or prompted, before the turn was queued, so the ten seconds
  # the tracker allows hold however long the queue takes.
  def thinking! = nil

  def step(key:, step:, status:, outcome: nil, **)
    done = status == FirefightAi::AgentLoop::STEP_DONE
    result = (OUTCOME_WORDS[outcome&.kind] || OUTCOME_WORDS.fetch(Chat::StepOutcome::KIND_ANSWERED) if done)
    say(Integrations::AgentSessions::Activity.new(kind: Integrations::AgentSessions::ACTION, action: step.title,
                                                  parameter: (step.headline.presence || step.asked.presence || step.title).to_s, result: result,
                                                  ephemeral: !done))
  end

  # How far a long tool got, a helper's reads and making room are the dashboard's to show.
  def progress(**) = nil

  def activity(**) = nil

  def helpers(**) = nil

  def made_room(_compaction) = nil

  def switched_model(switch)
    say(Integrations::AgentSessions::Activity.new(kind: Integrations::AgentSessions::THOUGHT, body: switch.shown_as))
  end

  # The answer is posted whole once it is written, since an activity cannot be added to.
  def chunk(_text) = nil

  def answered!(reply, sources: [])
    body = [ reply, sources_line(sources), approval_line ].compact.join("\n\n")
    say(Integrations::AgentSessions::Activity.new(kind: Integrations::AgentSessions::RESPONSE, body: body))
  end

  def failed!(text = Conversation::Delivery::FAILED)
    say(Integrations::AgentSessions::Activity.new(kind: Integrations::AgentSessions::ERROR, body: text))
  end

  def confirm!(tool_calls)
    asked = tool_calls.map { |tool_call| "- #{confirmation_line(Chat::Tools.confirmation(tool_call))}" }
    body = [ "Before I go on, a person needs to confirm #{tool_calls.one? ? 'this' : 'these'}:", asked.join("\n"),
             "Confirm or skip #{tool_calls.one? ? 'it' : 'them'} in this chat in Firefight#{" (#{chat_url})" if chat_url}. " \
             "Asking something else here skips #{tool_calls.one? ? 'it' : 'them'}." ].join("\n\n")
    say(Integrations::AgentSessions::Activity.new(kind: Integrations::AgentSessions::ELICITATION, body: body))
  end

  # A confirmation left behind is withdrawn on the dashboard, and the issue has nothing to redraw.
  def withdrawn!(_tool_calls) = nil

  # A lost turn is said as failed right after, which is all the issue shows.
  def cut_off! = nil

  private

  def say(activity)
    session = @conversation.issue_session
    return unless session

    Integrations::AgentSessions.for(row(session)).say(session.session_id, activity)
  rescue Integrations::Error => error
    Rails.logger.warn({ event: "conversation.issue_activity_undelivered", conversation_id: @conversation.id, kind: activity.kind,
                        error: error.message.truncate(200) }.to_json)
  end

  def row(session) = session.integration.resolve_environment(nil) || raise(Integrations::Error, "#{session.integration.name} has no environment to call.")

  def confirmation_line(confirmation)
    [ confirmation.question, (" on #{confirmation.target}" if confirmation.target.present?) ].compact.join
  end

  # What Halon read, as one line under the answer, each read linked to its page when its result gave one.
  def sources_line(sources)
    return if sources.empty?

    listed = sources.first(SOURCES_SHOWN).map { |source| source.url.present? ? "[#{source.title.to_s.squish}](#{source.url})" : source.title.to_s.squish }
    more = sources.size - SOURCES_SHOWN
    "Read: #{listed.join(', ')}#{" and #{more} more" if more.positive?}"
  end

  # A call an approval rule held in this turn waits for an approver, and is run from the chat in Firefight once approved.
  def approval_line
    chat = @conversation.chat
    held = chat ? chat.held_calls.where(status: Chat::HeldCall::STATUS_WAITING, created_at: @since..).count : 0
    return if held.zero?

    approvals = url_for(:gateway_approvals_url)
    "#{held == 1 ? 'A call is' : "#{held} calls are"} waiting for approval. An approver decides under Gateway, Approvals#{" (#{approvals})" if approvals}, " \
      "and it runs from this chat in Firefight#{" (#{chat_url})" if chat_url} once approved."
  end

  def chat_url = url_for(:agent_chat_url, @conversation)

  def url_for(helper, *arguments)
    options = AppUrl.options
    options && Rails.application.routes.url_helpers.public_send(helper, *arguments, **options)
  end
end
