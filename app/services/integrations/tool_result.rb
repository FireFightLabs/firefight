module Integrations
  # Executors normalize on the way out, so callers read result["content"] without defending.
  module ToolResult
    def self.normalize(result)
      return result if result.is_a?(Hash) && result.key?("content")

      text = result.is_a?(String) ? result : JSON.pretty_generate(result)
      { "content" => [ { "type" => "text", "text" => text } ] }
    end
  end
end
