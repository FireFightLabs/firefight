module Integrations
  # The normalized shape every executor's discovery returns, whatever the
  # source (an MCP server's tools/list, a native pack's declarations).
  # DiscoveryService persists these without knowing the kind.
  ToolDefinition = Data.define(:name, :description, :params_schema, :read_only, :spec) do
    def initialize(name:, description:, params_schema:, read_only:, spec: {})
      super
    end
  end
end
