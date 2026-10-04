module Integrations
  # A first-party integration in Ruby, the native analogue of an MCP server.
  # The pack's tool declarations are the single source of truth for what the provider offers.
  class NativePack
    class Error < Integrations::Error; end

    # One value a pack connected with credentials (connect_with: api_token) asks for on the connect form. A secret one is
    # typed into a password field and never shown again. An optional one may be left empty, and the pack says what empty
    # means.
    CredentialField = Data.define(:key, :label, :hint, :placeholder, :secret, :optional) do
      def initialize(optional: false, **) = super
    end

    class << self
      # The pack a provider's definition names (Integrations::Provider), or nil. A provider whose registry entry declares
      # kind: native has one, so connect skips the server URL.
      def for(provider_key) = Provider.for(provider_key).pack

      # What Halon can do through the provider, in its own words, for a pack whose work is not a capability, such as a
      # coding agent. nil says it the usual way (Capabilities.halon_sentence).
      def halon_sentence(_name) = nil

      # Providers that gate access behind installing an app return the URL to send
      # the customer to. nil means no install-first flow.
      def install_url(state:)
        nil
      end

      def fetch!(integration, box_key: nil, progress: nil)
        pack_class = self.for(integration.provider)
        raise Error, "No native pack registered for '#{integration.provider}'" unless pack_class

        pack_class.new(integration, box_key: box_key, progress: progress)
      end

      def tool_definitions
        @tool_definitions ||= []
      end

      # A pack connected from a pasted URL (connect_with: connection_url) says why a URL and its certificates cannot be
      # used, or nil, and stores them on an environment row. It owns the credential's shape, so nothing else reads it.
      def connection_refusal(_url, _certificates)
        raise NotImplementedError, "#{name} does not connect from a URL"
      end

      def store_connection!(_environment_row, url:, certificates:)
        raise NotImplementedError, "#{name} does not connect from a URL"
      end

      # The certificates a pack connected from a URL may be given, pasted as text.
      def certificate_fields = []

      # A pack connected with credentials (connect_with: api_token) lists the fields it asks for, says why the values
      # cannot be used or nil, and stores them on an environment row. It owns their shape, so nothing else reads them.
      # region is the provider's region the person chose (IntegrationProvider::Region), or nil for a provider with one,
      # and fields what the form asked beside the credentials (the registry's connect_fields), so a pack can check that a
      # project or workspace it names exists before anything is saved. A pack reads what it stored through
      # ConnectionSettings#credential, and what the form asked through ConnectionSettings#field.
      def credential_fields = []

      def credential_refusal(_values, region: nil, fields: {})
        raise NotImplementedError, "#{name} does not connect with credentials"
      end

      def store_credentials!(_environment_row, _values)
        raise NotImplementedError, "#{name} does not connect with credentials"
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

    # box_key names the run a call belongs to, so tools that read code share that run's sandbox. progress hears how a
    # long running tool is going, through report.
    attr_reader :integration, :box_key

    def initialize(integration, box_key: nil, progress: nil)
      @integration = integration
      @box_key = box_key
      @progress = progress
    end

    # Tells whoever runs the tool how it is going, in a sentence. Nobody may be listening, as in a chat.
    def report(text)
      @progress&.call(text)
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

    # What the connection reaches, as a ResourceMap::Snapshot, for the resource map. nil means the pack puts nothing on
    # the map.
    def map_of(environment_row)
    end

    # What normal looks like for the given map resources, as ResourceMap::Baseline::Found readings over window. nil means
    # the pack reads no metrics.
    def baselines_of(environment_row, resources, window)
    end
  end
end
