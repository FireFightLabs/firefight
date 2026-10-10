# What a chat read before it asked for a code change: each call that only read, with what it gave back, by what the
# step is called. Halon's bookkeeping and calls that failed are left out.
module CodeAgent::ChatEvidence
  def self.for(chat, workspace, before: nil)
    return [] unless chat

    calls = chat.tool_calls.includes(:result).where.not(result_id: nil).order(:created_at, :id).to_a
    calls = calls.take_while { |call| call.tool_call_id != before } if before
    calls.filter_map do |call|
      next unless Chat::Tools.kind(call.name, workspace, call.arguments) == Chat::Tools::KIND_READ
      next if Chat::Tools.internal_names.include?(call.name.to_s) || call.failed

      CodeAgent::Request::Evidence.new(label: Chat::Tools.label(call.name, call.arguments, workspace: workspace).presence || call.name.to_s,
                                       text: FirefightAi::Evidence.unframe(call.result.content).body)
    end
  end
end
