# Real RubyLLM messages, so a reply shape the library drops fails here rather than in production.
module LlmResponseHelper
  def llm_reply(content: "", input: 0, output: 0, cache_read: 0, cache_write: 0, cost: 0.0, finish_reason: :stop, request_id: nil)
    content = content.to_json unless content.is_a?(String)
    RubyLLM::Message.new(
      role: :assistant,
      content: content,
      tokens: RubyLLM::Tokens.new(input:, output:, cache_read:, cache_write:),
      cost: { total: cost },
      finish_reason: finish_reason,
      raw: Faraday::Response.new(status: 200, body: { "id" => request_id })
    )
  end
end
