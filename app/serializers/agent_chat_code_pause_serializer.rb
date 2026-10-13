# A code change from this chat that reached its spending limit: what it spent, what Continue gives it, and whether this
# viewer may decide, shipped as a blocked reason so the card never decides from a status.
class AgentChatCodePauseSerializer < BaseSerializer
  object_as :pause

  type :string
  def id
    pause.id
  end

  type CodeAgentSession::Pause::STATUSES.map(&:inspect).join(" | ")
  def status
    pause.status
  end

  type :string
  def question
    CodeAgentSession::Pause::QUESTION
  end

  type :string
  def repository
    pause.repository
  end

  type :string, optional: true
  def saved_branch
    pause.saved_branch
  end

  # Such as "$2.03"
  type :string
  def spent
    CodeAgentSession.dollars(pause.session.spent_micros)
  end

  # What Continue gives it, such as "$2"
  type :string
  def next_budget
    CodeAgentSession.dollars(pause.budget_micros)
  end

  type :string, optional: true
  def decided_by
    pause.decided_by&.display_name
  end

  type :string, optional: true
  def decide_blocked_reason
    pause.decide_blocked_reason(options[:member]) if pause.offered?
  end

  type :string
  def at
    pause.created_at.utc.iso8601(3)
  end
end
