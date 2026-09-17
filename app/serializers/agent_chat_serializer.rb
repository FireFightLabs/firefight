class AgentChatSerializer < BaseSerializer
  object_as :conversation

  attributes(id: { type: :string })

  type :string
  def title
    conversation.display_title
  end

  type :string
  def preview
    conversation.preview
  end

  type :string
  def updatedAt
    conversation.updated_at.utc.iso8601
  end

  type :boolean
  def pinned
    conversation.pinned?
  end

  type :boolean
  def archived
    conversation.archived?
  end
end
