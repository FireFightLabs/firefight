module Integrations
  # Same contract as McpExecutor, so callers never branch on kind.
  class NativeExecutor
    # progress, when given, is called each time a long running tool has something to say, with a sentence or a
    # Chat::CodeFixProgress (NativePack#report).
    # request, for a tool that writes code, is who asked and what they said (CodeAgent::Request).
    # A tool on a connection whose app installation stopped, or lacks what the tool needs, answers why instead of calling
    # the provider (Installations.refusal).
    def self.call(tool:, environment_row:, arguments:, box_key: nil, progress: nil, request: nil)
      refused = Installations.refusal(environment_row, tool)
      return { "content" => [ { "type" => "text", "text" => refused } ], "isError" => true } if refused

      pack = NativePack.fetch!(tool.integration, box_key: box_key, progress: progress, request: request)
      arguments = Scopes.resolved(environment_row, arguments.to_h)
      result = ToolResult.normalize(pack.call(tool.remote_name, environment_row: environment_row, arguments: arguments))
      Redactions.apply(result, **Redactions.rules(tool.integration.provider))
    end

    def self.tool_definitions(integration)
      NativePack.fetch!(integration).tool_definitions
    end

    def self.check_health!(environment_row)
      NativePack.fetch!(environment_row.integration).check_health!(environment_row)
    end

    # A pack checks itself with its own API, never through its tools.
    def self.checks_through_tools?(_integration) = false

    def self.map_every(integration)
      pack = NativePack.for(integration.provider)
      pack&.const_defined?(:EVERY, false) ? pack::EVERY : McpExecutor::DEFAULT_MAP_EVERY
    end

    def self.map_of(environment_row)
      Installations.stopped!(environment_row)
      NativePack.fetch!(environment_row.integration).map_of(environment_row)
    end

    # A re-read of one scope after the provider said something there changed, or nil when the pack cannot narrow its
    # read to it (Integrations::MapEvents).
    def self.map_refresh(environment_row, scope)
      Installations.stopped!(environment_row)
      NativePack.fetch!(environment_row.integration).map_refresh(environment_row, scope)
    end

    def self.baselines_of(environment_row, resources, window)
      Installations.stopped!(environment_row)
      NativePack.fetch!(environment_row.integration).baselines_of(environment_row, resources, window)
    end
  end
end
