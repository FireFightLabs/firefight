module Integrations
  # Every executor's discovery returns this shape, so DiscoveryService never knows the kind.
  ToolDefinition = Data.define(:name, :description, :params_schema, :read_only, :spec) do
    def initialize(name:, description:, params_schema:, read_only:, spec: {})
      super
    end
  end
end
