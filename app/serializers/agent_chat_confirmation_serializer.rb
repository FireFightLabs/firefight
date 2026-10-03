# A call the agent paused on, put to the person as a question.
class AgentChatConfirmationSerializer < BaseSerializer
  object_as :tool_call

  type :string
  def toolCallId
    tool_call.tool_call_id
  end

  # The tool's own name, so allowing one call for the rest of the chat can answer the others asked about it.
  type :string
  def tool
    tool_call.name
  end

  type :string
  def question
    Chat::Tools.confirmation(tool_call).question
  end

  # What the call will do, in the agent's words for whoever approves it. Absent on calls saved before it was asked for.
  type :string, optional: true
  def intent
    Chat::Tools.confirmation(tool_call).intent
  end

  type "string[][]"
  def asked
    Chat::Tools.confirmation(tool_call).asked
  end
end
