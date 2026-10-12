# A message sent while the agent was working, shown until the agent reads it at its next step.
class AgentChatWaitingMessageSerializer < BaseSerializer
  object_as :message

  attributes(id: { type: :string })

  # Read as the platform shows it in a chat asked there, from the platform_texts handed in.
  type :string
  def body
    options.fetch(:platform_texts, {}).fetch(message.content, message.content)
  end

  has_many :attached_files, as: :attachments, serializer: AgentChatAttachmentSerializer
end
