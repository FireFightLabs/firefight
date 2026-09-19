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

  type :boolean
  def pinned
    conversation.pinned?
  end

  # The list sorts itself on these, so changes land in place without a reload.
  type "string | null"
  def pinnedAt
    conversation.pinned_at&.utc&.iso8601(3)
  end

  type :string
  def lastActiveAt
    conversation.updated_at.utc.iso8601(3)
  end

  type :boolean
  def archived
    conversation.archived?
  end
end
