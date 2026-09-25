# A message sent while the agent was working, shown until the agent reads it at its next step.
class AgentChatWaitingMessageSerializer < BaseSerializer
  object_as :message

  attributes(id: { type: :string })

  type :string
  def body
    message.content
  end
end
