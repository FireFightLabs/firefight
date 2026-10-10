# Whoever started what a call would stop, asked in their direct messages once the person confirmed, and their answer.
class AgentChatOwnerAskSerializer < BaseSerializer
  object_as :ask

  type :string
  def id
    ask.id
  end

  type :string
  def owner_name
    ask.owner_name
  end

  # What it would stop, such as "Cancel workflow Deploy run 46 (123) in acme/shop".
  type :string
  def headline
    ask.headline
  end

  type Chat::OwnerAsk::STATUSES.map(&:inspect).join(" | ")
  def status
    ask.status
  end

  type :string
  def at
    (ask.asked_at || ask.created_at).utc.iso8601(3)
  end
end
