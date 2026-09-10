module Integrations
  # A first-party integration in Ruby, the native analogue of an MCP server.
  # The pack's tool declarations are the single source of truth for what the provider offers.
  class NativePack
    class Error < Integrations::Error; end

    # Providers listed here execute through the pack instead of an MCP server, their
    # registry entry declares kind: native so connect skips the server URL.
    REGISTRY = {
      "github" => "Integrations::Packs::Github"
    }.freeze

    class << self
      def for(provider_key)
        REGISTRY[provider_key.to_s]&.constantize
      end

      # Providers that gate access behind installing an app return the URL to send
      # the customer to. nil means no install-first flow.
      def install_url(state:)
        nil
      end

      def fetch!(integration)
        pack_class = self.for(integration.provider)
        raise Error, "No native pack registered for '#{integration.provider}'" unless pack_class

        pack_class.new(integration)
      end

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

    def tool_definitions
      self.class.tool_definitions
    end

    def call(tool_name, environment_row:, arguments:)
      definition = tool_definitions.find { |candidate| candidate.name == tool_name }
      fail! "Unknown tool '#{tool_name}' for #{self.class.name}" unless definition

      public_send(definition.name, environment_row: environment_row, arguments: arguments)
    end

    # Inside a pack file a bare Error resolves to Integrations::Error, not this class.
    def fail!(message)
      raise Error, message
    end

    # Packs override with a real probe and raise Error with a readable reason.
    # The default accepts so a pack without a probe still connects.
    def check_health!(environment_row)
    end
  end
end
