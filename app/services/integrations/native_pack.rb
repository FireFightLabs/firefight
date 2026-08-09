module Integrations
  # A first-party integration implemented in Ruby: the native analogue of an
  # external MCP server. A subclass declares its tools in code and implements
  # one instance method per tool; discovery reads the declarations and the
  # executor dispatches to the methods, so the pack is the single source of
  # truth for what a native provider offers.
  class NativePack
    class Error < StandardError; end

    ToolDefinition = Data.define(:name, :description, :params_schema, :read_only)

    class << self
      def tool_definitions
        @tool_definitions ||= []
      end

      def tool(name, description:, params_schema:, read_only:)
        name = name.to_s
        unless name.match?(/\A[a-z0-9_]+\z/)
          raise ArgumentError, "Tool name '#{name}' must be a valid method name (a-z, 0-9, _)"
        end

        tool_definitions << ToolDefinition.new(
          name: name, description: description, params_schema: params_schema, read_only: read_only
        )
      end
    end

    attr_reader :integration

    def initialize(integration)
      @integration = integration
    end

    def call(tool_name, environment_row:, arguments:)
      definition = self.class.tool_definitions.find { |candidate| candidate.name == tool_name }
      raise Error, "Unknown tool '#{tool_name}' for #{self.class.name}" unless definition

      public_send(definition.name, environment_row: environment_row, arguments: arguments)
    end

    # Probes the provider with the row's credentials. Packs override with a
    # real call and raise Error with a readable reason on failure; the
    # default accepts so a pack without a probe still connects.
    def check_health!(environment_row)
    end
  end
end
