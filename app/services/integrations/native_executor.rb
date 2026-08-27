module Integrations
  # Everything kind: native knows about talking to its provider, all of it
  # delegated to the registered Integrations::NativePack. Same contract as
  # McpExecutor, so callers never branch on kind.
  class NativeExecutor
    def self.call(tool:, environment_row:, arguments:)
      pack = NativePack.fetch!(tool.integration)
      ToolResult.normalize(pack.call(tool.remote_name, environment_row: environment_row, arguments: arguments))
    end

    def self.tool_definitions(integration)
      NativePack.fetch!(integration).tool_definitions
    end

    def self.check_health!(environment_row)
      NativePack.fetch!(environment_row.integration).check_health!(environment_row)
    end
  end
end
