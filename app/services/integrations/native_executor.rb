module Integrations
  # Runs an authorized tool call against a first-party pack. Same contract as
  # McpExecutor: the gateway has already said yes, this only executes. Results
  # are normalized into MCP content shape so callers stay executor-agnostic.
  class NativeExecutor
    def self.call(tool:, environment_row:, arguments:)
      pack = NativePacks.fetch!(tool.integration)
      normalize(pack.call(tool.remote_name, environment_row: environment_row, arguments: arguments))
    end

    def self.normalize(result)
      return result if result.is_a?(Hash) && result.key?("content")

      text = result.is_a?(String) ? result : JSON.pretty_generate(result)
      { "content" => [ { "type" => "text", "text" => text } ] }
    end
  end
end
