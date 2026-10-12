# Someone assigned an issue in a connected tracker to Firefight's app, mentioned it there, wrote again in that session,
# or asked it to stop (Integrations::AgentSessions). A session is a chat like any other, answered in the issue
# (Conversation::IssueDelivery), and it acts as Firefight's own agent, never as the person who asked, since a machine
# holds only what an admin granted it. The session is told Halon is on it before anything else, since the tracker marks
# one that stays silent for ten seconds as unresponsive.
class Conversation::IssueSessions
  ON_IT = "Looking into it.".freeze
  NOTHING_TO_STOP = "Stopped. I was not working on anything here.".freeze
  CHAT_LABEL = "Open in Firefight".freeze
  CONTEXT_FRAME = "issue".freeze

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
    when Integrations::AgentSessions::PROMPTED then asked(@event.text)
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
    conversation = Conversation.start_in_issue!(
      integration: @integration, session_id: @event.session_id, title: [ @event.issue_key, @event.issue_title ].compact.join(" "),
      issue_key: @event.issue_key, issue_url: @event.issue_url, asked_by: asked_by
    )
    link(conversation)
    conversation
  end

  # The session points at its chat, so anyone in the issue can open it in Firefight.
  def link(conversation)
    options = AppUrl.options
    return unless options

    url = Rails.application.routes.url_helpers.agent_chat_url(conversation, **options)
    Integrations::AgentSessions.for(@row).link(@event.session_id, label: CHAT_LABEL, url: url)
  rescue Integrations::Error => error
    Rails.logger.warn({ event: "conversation.issue_link_undelivered", conversation_id: conversation.id, error: error.message.truncate(200) }.to_json)
  end

  # The member the tracker's person is, by an exact email, whose chat list shows the chat.
  def asked_by
    email = @event.asker_email.to_s.strip.downcase
    email.present? ? @workspace.workspace_memberships.joins(:user).find_by("lower(users.email) = ?", email) : nil
  end

  def asked_by_label
    place = Conversation::IssueSession.new(integration: @integration).place
    "#{@event.asker_name.presence || 'Someone'} in #{place}"
  end

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

  def say(kind, body)
    Integrations::AgentSessions.for(@row).say(@event.session_id, Integrations::AgentSessions::Activity.new(kind: kind, body: body))
  rescue Integrations::Error => error
    Rails.logger.warn({ event: "conversation.issue_activity_undelivered", session: @event.session_id, kind: kind, error: error.message.truncate(200) }.to_json)
  end
end
