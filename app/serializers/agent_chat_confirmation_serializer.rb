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
    confirmation.question
  end

  type :string
  def tool_label
    confirmation.tool_label
  end

  # What the call will do, in the agent's words for whoever approves it. Absent on calls saved before it was asked for.
  type :string, optional: true
  def intent
    confirmation.intent
  end

  type "string[][]"
  def asked
    confirmation.asked
  end

  # What the call reaches, such as "Faylee (Northflank), project faylee", from the tool and never the agent's words.
  # Absent for Firefight's own tools and on calls asked before it was kept.
  type :string, optional: true
  def target
    confirmation.target
  end

  # What the tool does, such as "Api request", when there is a target.
  type :string, optional: true
  def call_name
    confirmation.call
  end

  private

  def confirmation = memo.fetch(:confirmation) { Chat::Tools.confirmation(tool_call) }
end
