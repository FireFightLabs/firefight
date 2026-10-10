# A change customers feel that Halon made in this chat, with what it changed, when Firefight undoes it, how, and how it
# ended. Whether the viewer may keep, extend or undo it ships as blocked reasons, so the card decides nothing.
class AgentChatMitigationSerializer < BaseSerializer
  object_as :mitigation

  type :string
  def id
    mitigation.id
  end

  type :string
  def title
    mitigation.title
  end

  # The call and what it reaches, such as "Feature flag disable on Product (PostHog)".
  type :string
  def label
    mitigation.label
  end

  type Chat::Mitigation::STATUSES.map(&:inspect).join(" | ")
  def status
    mitigation.status
  end

  type :string, optional: true
  def expires_at
    mitigation.expires_at&.utc&.iso8601
  end

  type Chat::Mitigation::UNDO_STATES.map(&:inspect).join(" | ")
  def undo_state
    mitigation.undo_state
  end

  # How it is undone, or what a person has to do by hand.
  type :string, optional: true
  def undo_note
    mitigation.undo_note
  end

  type :string, optional: true
  def outcome
    mitigation.outcome
  end

  # Placed among the chat's messages by when it ran.
  type :string
  def at
    (mitigation.started_at || mitigation.created_at).utc.iso8601(3)
  end

  type :string, optional: true
  def keep_blocked_reason = mitigation.keep_blocked_reason(options[:member])

  type :string, optional: true
  def extend_blocked_reason = mitigation.extend_blocked_reason(options[:member])

  type :string, optional: true
  def undo_blocked_reason = mitigation.undo_blocked_reason(options[:member])
end
