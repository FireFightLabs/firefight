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

  # The same shape the page gets while a turn is running, so a step reads the same either way.
  type "{ key: string; title: string; asked: [string, string][]; status: string }[]"
  def tools
    message.ruby_llm_tool_calls.map do |call|
      {
        key: call.tool_call_id,
        title: Chat::Tools.step_title(call.name),
        asked: call.arguments.to_h.filter_map { |name, value| [ name.to_s, value.to_s.truncate(60) ] if value.present? },
        status: call.result_id.present? ? Conversation::LiveDelivery::STATUS_DONE : Conversation::LiveDelivery::STATUS_RUNNING
      }
    end
  end
end
