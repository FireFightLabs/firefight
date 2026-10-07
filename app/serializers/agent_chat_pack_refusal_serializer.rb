# A change Halon was refused in this chat for want of a pack, with what the viewer may do about it. Only the person
# refused may ask, and only once a day, which ships as a blocked reason so the card decides nothing.
class AgentChatPackRefusalSerializer < BaseSerializer
  object_as :refusal

  type :string
  def id
    refusal.id
  end

  type :string
  def headline
    refusal.headline
  end

  type :string
  def body
    refusal.body
  end

  type :string, optional: true
  def asked_line
    refusal.asked_line
  end

  type :string, optional: true
  def ask_blocked_reason
    refusal.pack_request.ask_blocked_reason(options[:member])
  end

  # When it happened, which is where it sits among the chat's messages.
  type :string
  def at
    refusal.created_at.utc.iso8601(3)
  end
end
