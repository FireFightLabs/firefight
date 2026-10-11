# The suspects a troubleshooting turn starts from (ResourceMap::Suspects), told before Halon's first model call of the
# turn. A turn troubleshoots when its chat is about an incident, whose resources are what fails, or when the person's
# words name a resource on the map. Any other turn, a plain question, gets nothing, and a list the chat was already told
# is not told again.
module Conversation::Suspects
  # The newest notes compared, so the same list is never told twice in a row.
  TOLD_READ = 20

  # The list as a note, or nil.
  def self.note(turn, words)
    workspace = turn.workspace
    principal = turn.acting_principal
    return nil unless principal

    roots, anchor = roots_of(turn, words)
    return nil if roots.empty?

    text = ResourceMap::Suspects.new(workspace: workspace, principal: principal, roots: roots, anchor: anchor, from: anchor - ResourceMap::Suspects::LEAD).text
    text unless text.nil? || told?(turn.chat, text)
  end

  def self.roots_of(turn, words)
    incident = turn.incident
    if incident
      subject, = ResourceMap::Timeline.for_incident(turn.workspace, turn.acting_principal, incident)
      return [ subject.resources, incident.detected_at || incident.declared_at || Time.current ] if subject.resources.any?
    end

    [ ResourceMap::Suspects.named_in(turn.workspace, turn.acting_principal, words), Time.current ]
  end

  def self.told?(chat, text)
    return false unless chat

    chat.messages.where(role: Chat::Message::ROLE_USER, nudge: true).reorder(created_at: :desc).limit(TOLD_READ).any? { |message| message.content == text }
  end
  private_class_method :roots_of, :told?
end
