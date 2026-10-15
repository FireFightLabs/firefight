# What Halon says while it answers in a tracker's issue, as activities in the session someone opened there by assigning
# the issue to Firefight's app or mentioning it (Integrations::AgentSessions). Each tool is an action, shown while it
# runs and kept once it answered with how it went, and the answer is the response. Nobody opens the chat in Firefight,
# so what needs a person is decided without it. A call to confirm is asked with Confirm and Skip to pick in the issue
# (Conversation::IssueSessions takes the answer), and a call an approval rule holds is said under the answer with a link
# to Gateway, Approvals, where approving it runs it (Conversation::HeldCalls). A failure to say something is logged and
# never retried, since the answer is saved in the chat.
class Conversation::IssueDelivery
  OUTCOME_WORDS = {
    Chat::StepOutcome::KIND_ANSWERED => "Done", Chat::StepOutcome::KIND_FAILED => "Failed",
    Chat::StepOutcome::KIND_NOT_FOUND => "Not found", Chat::StepOutcome::KIND_REFUSED => "Not allowed",
    Chat::StepOutcome::KIND_STOPPED => "Stopped"
  }.freeze
  SOURCES_SHOWN = 8
  # What a person picks in the issue to answer a call to confirm, which comes back as a follow up saying it.
  CONFIRM = "Confirm".freeze
  SKIP = "Skip".freeze

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
    body = [ Chat::Chart::Marker.strip(reply), sources_line(sources), approval_line ].compact.join("\n\n")
    say(Integrations::AgentSessions::Activity.new(kind: Integrations::AgentSessions::RESPONSE, body: body))
  end

  def failed!(text = Conversation::Delivery::FAILED)
    say(Integrations::AgentSessions::Activity.new(kind: Integrations::AgentSessions::ERROR, body: text))
  end

  def confirm!(tool_calls)
    asked = tool_calls.map { |tool_call| "- #{confirmation_line(Chat::Tools.confirmation(tool_call))}" }
    them = tool_calls.one? ? "it" : "them"
    body = [ "Before I go on, a person needs to confirm #{tool_calls.one? ? 'this' : 'these'}:", asked.join("\n"),
             "Choose #{CONFIRM} to go ahead or #{SKIP} to leave #{them}. Only someone with a Firefight account who may ask Halon " \
             "can answer, and asking something else here skips #{them}." ].join("\n\n")
    say(Integrations::AgentSessions::Activity.new(kind: Integrations::AgentSessions::ELICITATION, body: body, choices: [ CONFIRM, SKIP ]))
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

  # A call an approval rule held in this turn waits for an approver, and runs as soon as it is approved.
  def approval_line
    chat = @conversation.chat
    held = chat ? chat.held_calls.where(status: Chat::HeldCall::STATUS_WAITING, created_at: @since..).count : 0
    return if held.zero?

    options = AppUrl.options
    approvals = options && Rails.application.routes.url_helpers.gateway_approvals_url(**options)
    "#{held == 1 ? 'A call is' : "#{held} calls are"} waiting for approval. An approver decides under Gateway, Approvals in Firefight" \
      "#{" (#{approvals})" if approvals}, and #{held == 1 ? 'it runs' : 'each runs'} as soon as it is approved."
  end
end
