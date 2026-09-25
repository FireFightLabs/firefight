class AgentChatMessageSerializer < BaseSerializer
  object_as :message

  attributes(id: { type: :string }, role: { type: :string })

  type :string
  def body
    message.content.to_s
  end

  # Same shape as the live step event, so a step reads the same either way.
  type "{ key: string; title: string; headline: string; asked: [string, string][]; status: string; kind: string; seconds: number; card: { kind: string; category: string | null } | null }[]"
  def tools
    workspace = message.chat.workspace
    calls = message.ruby_llm_tool_calls.sort_by(&:created_at)
    charted = message.chat.charts.unscope(:order).where(tool_call_id: calls.map(&:tool_call_id)).distinct.pluck(:tool_call_id).to_set
    calls.filter_map do |call|
      step = Chat::Tools.step(call.name, call.arguments)
      next unless step

      status = self.class.step_status(call)
      { key: call.tool_call_id, title: step.title, headline: step.headline, asked: step.asked,
        status: status, kind: Chat::Tools.kind(call.name, workspace),
        seconds: self.class.step_seconds(call, message, last: call == calls.last),
        card: (card_for(step, call, charted)&.to_h if status == Conversation::LiveDelivery::STATUS_DONE) }
    end
  end

  def card_for(step, call, charted)
    step.card || (Chat::Tools.chart_card if charted.include?(call.tool_call_id))
  end

  # What the page adds up for "thought for n seconds", counted from when the model started this reply, so the time it
  # spent deciding counts as thinking too. Only the last call of a message carries it, or calls made together in one
  # reply would each count the same stretch.
  def self.step_seconds(call, message, last:)
    finished = call.result&.created_at
    return 0 unless last && finished

    (finished - message.created_at).round
  end

  STEP_STATUS_BY_APPROVAL = {
    Chat::APPROVAL_REQUESTED => Conversation::LiveDelivery::STATUS_WAITING,
    Chat::APPROVAL_DENIED => Conversation::LiveDelivery::STATUS_CANCELLED
  }.freeze

  def self.step_status(call)
    STEP_STATUS_BY_APPROVAL.fetch(call.approval) do
      next Conversation::LiveDelivery::STATUS_FAILED if call.failed
      call.result_id.present? ? Conversation::LiveDelivery::STATUS_DONE : Conversation::LiveDelivery::STATUS_RUNNING
    end
  end
end
