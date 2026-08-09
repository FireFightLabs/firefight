module Integrations
  # Selects the executor for an integration's kind. The one place the kinds
  # diverge - the gateway and the outward MCP registry never branch on kind,
  # so governance stays executor-agnostic.
  class Executor
    def self.for(integration)
      case integration.kind
      when Integration::KIND_MCP then McpExecutor
      when Integration::KIND_NATIVE then NativeExecutor
      else
        raise NativePack::Error, "No executor implemented for kind '#{integration.kind}'"
      end
    end
  end
end
