# A secret a tool call in this chat handed to the person who asked, either a value to type, or a credential to reveal. Never the
# value. Who may act and why not ships as a blocked reason, so the card decides nothing.
class AgentChatSecretEntrySerializer < BaseSerializer
  object_as :entry

  type :string
  def id
    entry.id
  end

  type :string
  def kind
    entry.kind
  end

  type :string
  def headline
    entry.headline
  end

  type :string
  def body
    entry.body
  end

  type :string, optional: true
  def status_line
    entry.status_line
  end

  # Whether the field can still be filled or the credential revealed, by someone.
  type :boolean
  def open
    entry.open?
  end

  # Why this viewer cannot, while it is open.
  type :string, optional: true
  def blocked_reason
    return nil unless entry.open?

    entry.enter? ? entry.fill_blocked_reason(options[:member]) : entry.reveal_blocked_reason(options[:member])
  end

  # When it happened, which is where it sits among the chat's messages.
  type :string
  def at
    entry.at
  end
end
