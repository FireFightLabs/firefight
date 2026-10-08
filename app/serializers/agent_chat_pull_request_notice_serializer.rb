# A pull request Halon opened from this chat that needs attention: why, what Fix it would do, and whether this viewer may
# press it, shipped as a blocked reason so the card never decides from a status.
class AgentChatPullRequestNoticeSerializer < BaseSerializer
  object_as :notice

  type :string
  def id
    notice.id
  end

  type CodeAgentSession::Notice::STATUSES.map(&:inspect).join(" | ")
  def status
    notice.status
  end

  # Such as "PR #689 in acme/api needs attention"
  type :string
  def headline
    notice.headline
  end

  # Why, under the headline, such as "It conflicts with main now."
  type :string
  def reason
    notice.why
  end

  type :string
  def offer
    notice.offer
  end

  type :string, optional: true
  def url
    notice.session.pull_request_url
  end

  # Who pressed Fix it, once someone did.
  type :string, optional: true
  def fixed_by
    notice.fix_by&.display_name
  end

  type :string, optional: true
  def fix_blocked_reason
    notice.fix_blocked_reason(options[:member]) if notice.offered?
  end

  type :string
  def at
    notice.created_at.utc.iso8601(3)
  end
end
