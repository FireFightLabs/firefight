class AgentChatSerializer < BaseSerializer
  object_as :conversation

  attributes(id: { type: :string })

  type :string
  def title
    conversation.opening_line.presence || "New chat"
  end

  type :string
  def updatedAt
    conversation.updated_at.utc.iso8601
  end

  type :number
  def spentCents
    conversation.spent_cents
  end
end
