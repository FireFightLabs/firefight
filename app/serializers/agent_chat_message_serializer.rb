# What the dashboard renders: who spoke, what they said, and the tools behind an answer.
class AgentChatMessageSerializer < BaseSerializer
  object_as :message

  attributes(id: { type: :string }, role: { type: :string })

  type :string
  def body
    message.content.to_s
  end

  type :string
  def at
    message.created_at.utc.iso8601
  end

  type "{ id: string; name: string; answered: boolean }[]"
  def tools
    message.ruby_llm_tool_calls.map do |call|
      { id: call.tool_call_id, name: call.name, answered: call.result_id.present? }
    end
  end
end
