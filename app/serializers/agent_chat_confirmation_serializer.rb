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

  # What the call reaches, such as "Production (Acme Cloud), project shop", from the tool and never the agent's words.
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

  # Whether Allow for the rest of this chat is offered, which it is not once something was read from outside.
  type :boolean
  def allowable
    confirmation.allowable?
  end

  # What was read from outside before the call was asked, led by one sentence. Absent when nothing was.
  type :string, optional: true
  def read_lead
    confirmation.read_lead
  end

  type "string[][]"
  def read_rows
    confirmation.read_rows
  end

  # What the call touches beyond its arguments, such as the rows a statement changes or who started what it stops.
  type "string[][]"
  def safeguards
    confirmation.safeguards
  end

  # When a change customers feel may be undone, the default first. Empty for any other call.
  type "{ value: string; label: string }[]"
  def expires
    confirmation.expires.map(&:to_h)
  end

  private

  def confirmation = memo.fetch(:confirmation) { Chat::Tools.confirmation(tool_call) }
end
