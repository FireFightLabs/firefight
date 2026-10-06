module Integrations
  # Same contract as McpExecutor, so callers never branch on kind.
  class NativeExecutor
    # progress, when given, is called with a sentence each time a long running tool has something to say.
    def self.call(tool:, environment_row:, arguments:, box_key: nil, progress: nil)
      pack = NativePack.fetch!(tool.integration, box_key: box_key, progress: progress)
      result = ToolResult.normalize(pack.call(tool.remote_name, environment_row: environment_row, arguments: arguments))
      Redactions.apply(result, fields: Provider.for(tool.integration.provider).redacted_fields)
    end

    def self.tool_definitions(integration)
      NativePack.fetch!(integration).tool_definitions
    end

    def self.check_health!(environment_row)
      NativePack.fetch!(environment_row.integration).check_health!(environment_row)
    end

    # A pack checks itself with its own API, never through the tools an admin switches on.
    def self.checks_through_tools?(_integration) = false

    def self.map_every(integration)
      pack = NativePack.for(integration.provider)
      pack&.const_defined?(:EVERY, false) ? pack::EVERY : McpExecutor::DEFAULT_MAP_EVERY
    end

    def self.map_of(environment_row)
      NativePack.fetch!(environment_row.integration).map_of(environment_row)
    end

    # A re-read of one scope after the provider said something there changed, or nil when the pack cannot narrow its
    # read to it (Integrations::MapEvents).
    def self.map_refresh(environment_row, scope)
      NativePack.fetch!(environment_row.integration).map_refresh(environment_row, scope)
    end

    def self.baselines_of(environment_row, resources, window)
      NativePack.fetch!(environment_row.integration).baselines_of(environment_row, resources, window)
    end
  end
end
