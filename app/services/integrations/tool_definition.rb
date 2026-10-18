module Integrations
  # Every executor's discovery returns this shape, so DiscoveryService never knows the kind. description is what the
  # model reads, summary the one line a person reads (Integrations::ToolSummaries), which a remote server never gives.
  ToolDefinition = Data.define(:name, :description, :params_schema, :read_only, :spec, :summary) do
    def initialize(name:, description:, params_schema:, read_only:, spec: {}, summary: nil)
      super
    end
  end
end
