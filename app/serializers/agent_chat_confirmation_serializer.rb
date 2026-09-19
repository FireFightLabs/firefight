# A call the agent paused on, put to the person as a question.
class AgentChatConfirmationSerializer < BaseSerializer
  object_as :tool_call

  type :string
  def toolCallId
    tool_call.tool_call_id
  end

  type :string
  def question
    Chat::Tools.confirmation(tool_call).question
  end

  type "string[][]"
  def asked
    Chat::Tools.confirmation(tool_call).asked
  end
end
