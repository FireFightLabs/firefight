# Someone assigned an issue in a connected tracker to Firefight's app, mentioned it there, wrote again in that session,
# or asked it to stop (Integrations::AgentSessions). A session is a chat like any other, answered in the issue
# (Conversation::IssueDelivery), and it acts as Firefight's own agent, never as the person who asked, since a machine
# holds only what an admin granted it. The session is told Halon is on it before anything else, since the tracker marks
# one that stays silent for ten seconds as unresponsive. Like a chat in a channel, it lives only in the issue, and no
# dashboard lists or opens it.
class Conversation::IssueSessions
  ON_IT = "Looking into it.".freeze
  NOTHING_TO_STOP = "Stopped. I was not working on anything here.".freeze
  CONTEXT_FRAME = "issue".freeze
  GOING_AHEAD = "Confirmed. Going ahead.".freeze
  SKIPPED = "Skipped. Carrying on without it.".freeze
  STILL_WAITING = "Only someone with a Firefight account who may ask Halon can answer this, so it is still waiting. " \
                  "Choose %<confirm>s or %<skip>s from the %<place>s account that uses the same email as theirs in Firefight.".freeze
  # Each word a person can pick to answer a call to confirm, and whether it goes ahead.
  CHOICES = { Conversation::IssueDelivery::CONFIRM.downcase => true, Conversation::IssueDelivery::SKIP.downcase => false }.freeze

  def self.receive!(environment_row, event)
    new(environment_row, event).receive!
  end

  def initialize(environment_row, event)
    @row = environment_row
    @integration = environment_row.integration
    @workspace = @integration.workspace
    @event = event
  end

  def receive!
    case @event.kind
    when Integrations::AgentSessions::STARTED then asked(@event.text || issue_named, context: opening_context)
    when Integrations::AgentSessions::PROMPTED then confirmation_answered? || asked(@event.text)
    when Integrations::AgentSessions::STOPPED then stop
    end
  end

  private

  def asked(text, context: nil)
    say(Integrations::AgentSessions::THOUGHT, ON_IT)
    refused = Investigation.unavailable_reason(@workspace)
    return say(Integrations::AgentSessions::ERROR, refused) if refused

    existing = Conversation.in_issue_session(@integration, @event.session_id)
    conversation = existing || opened
    # A session whose opening was missed starts from its first follow up, with what the tracker said of the issue.
    context ||= opening_context unless existing
    Conversation.ask_from_issue!(workspace: @workspace, asked_by_label: asked_by_label) do
      Conversation::Asking.ask(conversation, text, asker: conversation.started_by, context: context)
    end
  end

  def stop
    conversation = Conversation.in_issue_session(@integration, @event.session_id)
    return conversation.request_stop! if conversation&.answer_owed?

    say(Integrations::AgentSessions::RESPONSE, NOTHING_TO_STOP)
  end

  def opened
    Conversation.start_in_issue!(
      integration: @integration, session_id: @event.session_id, title: [ @event.issue_key, @event.issue_title ].compact.join(" "),
      issue_key: @event.issue_key, issue_url: @event.issue_url, asked_by: asked_by
    )
  end

  # A follow up picking Confirm or Skip answers every call the turn paused on, as the member who picked it, the way a
  # button in a channel does. It counts only from someone matched to a member who may ask Halon, which the gateway
  # decides and ledgers, and anyone else is told it still waits. Anything else is a question, which skips the calls as
  # asking something else on the dashboard does. Answers whether it was taken as an answer.
  def confirmation_answered?
    go_ahead = CHOICES[@event.text.to_s.strip.downcase.delete_suffix(".")]
    return false if go_ahead.nil?

    conversation = Conversation.in_issue_session(@integration, @event.session_id)
    waiting = conversation&.chat&.awaiting_decision.to_a
    return false if waiting.empty?

    member = asked_by
    return still_waiting unless member

    answered = Conversation.answer_in_issue!(member: member, workspace: @workspace, asked_by_label: asked_by_label) do
      Conversation::Confirming.decide(conversation, waiting.map { |call| { tool_call_id: call.tool_call_id, approved: go_ahead } }, by: member)
    end
    return still_waiting unless answered

    say(Integrations::AgentSessions::THOUGHT, go_ahead ? GOING_AHEAD : SKIPPED)
    true
  end

  def still_waiting
    body = format(STILL_WAITING, confirm: Conversation::IssueDelivery::CONFIRM, skip: Conversation::IssueDelivery::SKIP, place: place)
    choices = [ Conversation::IssueDelivery::CONFIRM, Conversation::IssueDelivery::SKIP ]
    say(Integrations::AgentSessions::ELICITATION, body, choices: choices)
    true
  end

  # The member the tracker's person is, by an exact email.
  def asked_by
    email = @event.asker_email.to_s.strip.downcase
    email.present? ? @workspace.workspace_memberships.joins(:user).find_by("lower(users.email) = ?", email) : nil
  end

  def asked_by_label = "#{@event.asker_name.presence || 'Someone'} in #{place}"

  def place = Conversation::IssueSession.new(integration: @integration).place

  # Assigning an issue says nothing in words, so the issue itself is the question.
  def issue_named = "Look into #{[ @event.issue_key, @event.issue_title ].compact.join(' ').presence || 'this issue'}."

  # What the tracker gathered about the issue, its comments and the team's guidance, which Halon reads before the
  # question and the page does not show. Anyone who can write in the issue wrote it, so it is framed as evidence.
  def opening_context
    where = [ @event.issue_key, @event.issue_url ].compact.join(" ")
    lines = [ "This chat was started from an issue#{" (#{where})" if where.present?} by someone assigning it to Firefight or mentioning it there." ]
    if @event.context.present?
      lines << "What the tracker says of the issue, its comments and the team's guidance:\n#{FirefightAi::Evidence.frame(CONTEXT_FRAME, @event.context)}"
    end
    lines.join("\n\n")
  end

  def say(kind, body, choices: [])
    Integrations::AgentSessions.for(@row).say(@event.session_id, Integrations::AgentSessions::Activity.new(kind: kind, body: body, choices: choices))
  rescue Integrations::Error => error
    Rails.logger.warn({ event: "conversation.issue_activity_undelivered", session: @event.session_id, kind: kind, error: error.message.truncate(200) }.to_json)
  end
end
