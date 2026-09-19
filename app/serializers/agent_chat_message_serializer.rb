class AgentChatMessageSerializer < BaseSerializer
  object_as :message

  attributes(id: { type: :string }, role: { type: :string })

  type :string
  def body
    message.content.to_s
  end

  # Same shape as the live step event, so a step reads the same either way.
  type "{ key: string; title: string; headline: string; asked: [string, string][]; status: string }[]"
  def tools
    message.ruby_llm_tool_calls.filter_map do |call|
      step = Chat::Tools.step(call.name, call.arguments)
      next unless step

      status = call.result_id.present? ? Conversation::LiveDelivery::STATUS_DONE : Conversation::LiveDelivery::STATUS_RUNNING
      { key: call.tool_call_id, title: step.title, headline: step.headline, asked: step.asked, status: status }
    end
  end
end
