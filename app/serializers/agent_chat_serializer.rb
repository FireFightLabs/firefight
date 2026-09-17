class AgentChatSerializer < BaseSerializer
  object_as :conversation

  attributes(id: { type: :string })

  type :string
  def title
    conversation.display_title
  end
end
