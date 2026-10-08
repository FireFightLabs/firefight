module Integrations
  # A first-party integration in Ruby, the native analogue of an MCP server.
  # The pack's tool declarations are the single source of truth for what the provider offers.
  class NativePack
    class Error < Integrations::Error; end

    # One value a pack connected with credentials (connect_with: api_token) asks for on the connect form. A secret one is
    # typed into a password field and never shown again. An optional one may be left empty, and the pack says what empty
    # means. A multiline one is pasted into a text area, such as a service account's JSON key, and is still never shown
    # again.
    CredentialField = Data.define(:key, :label, :hint, :placeholder, :secret, :optional, :multiline) do
      def initialize(optional: false, multiline: false, **) = super
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

      def fetch!(integration, box_key: nil, progress: nil, request: nil)
        pack_class = self.for(integration.provider)
        raise Error, "No native pack registered for '#{integration.provider}'" unless pack_class

        pack_class.new(integration, box_key: box_key, progress: progress, request: request)
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

      # A pack whose connect form chooses what the connection reads (a scope field, such as Northflank's projects) lists
      # what its credentials can read, as IntegrationProvider::ConnectOptions of an id and a name, and raises its
      # provider's refusal in words. values, region and fields are what the connect form gave.
      def scope_options(_values, region: nil, fields: {})
        raise NotImplementedError, "#{name} does not list what its credentials can read"
      end

      # The same for a connection already made, from what it stored and what its form asked.
      def scope_options_of(settings)
        values = credential_fields.to_h { |field| [ field.key, settings.credential(field.key) ] }
        fields = IntegrationProvider.find(settings.provider_key).connect_fields.reject(&:scope).to_h { |field| [ field.key, settings.field(field.key) ] }
        scope_options(values, region: settings.region, fields: fields.compact)
      end

      # The arguments that name a resource the pack's tools act on, which say which scope a call reaches when the
      # connection reaches several (Integrations::Scopes). A pack whose tools name one another way answers them too.
      def scope_references(arguments) = [ arguments["resource"] ]

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
    # long running tool is going, through report. request is the CodeAgent::Request a code change was asked with, who
    # asked and what they said, nil for any other call.
    attr_reader :integration, :box_key, :request

    def initialize(integration, box_key: nil, progress: nil, request: nil)
      @integration = integration
      @box_key = box_key
      @progress = progress
      @request = request
    end

    # Tells whoever runs the tool how it is going, in a sentence, or as a Chat::CodeFixProgress for a coding agent working in
    # the sandbox, handed over again each time it moves. Nobody may be listening.
    def report(update)
      @progress&.call(update)
    end

    def tool_definitions
      self.class.tool_definitions
    end

    # The scope a call reaches when given one (Integrations::Scopes.resolved names it in the arguments), read by scope!.
    def call(tool_name, environment_row:, arguments:)
      definition = tool_definitions.find { |candidate| candidate.name == tool_name }
      fail! "Unknown tool '#{tool_name}' for #{self.class.name}" unless definition

      key = environment_row && ConnectionSettings.of(environment_row).scope_field&.key
      @scope = arguments[key].to_s.strip.presence if key && @scope.nil?
      public_send(definition.name, environment_row: environment_row, arguments: arguments)
    end

    # The scope this pack reads, such as one Northflank project, for a connection that may reach several, or nil while it
    # was told none.
    attr_reader :scope

    # The same pack reading only scope, holding nothing another scope's reads cached.
    def scoped(scope)
      self.class.new(integration, box_key: box_key, progress: @progress, request: request).tap { |pack| pack.instance_variable_set(:@scope, scope&.to_s) }
    end

    # The one scope a call reaches, the one it was given or the connection's only one. A connection that reaches several
    # and was not told which refuses with the ones to choose from, so a call never lands in one picked for it. nil for an
    # optional field left empty.
    def scope!(environment_row)
      return @scope if @scope

      settings = ConnectionSettings.of(environment_row)
      field = settings.scope_field || fail!("#{settings.display_name} names nothing it reads.")
      return settings.chosen_scopes.first if settings.chosen_scopes.one? && !settings.all_scopes?
      # An optional field left empty reads what the credential itself reaches, such as a token made for one team.
      return if field.optional && settings.chosen_scopes.empty?

      reached = settings.scopes
      return reached.first if reached.one?
      fail!("#{settings.display_name} reaches no #{field.one} yet. Choose one on the Integrations page.") if reached.empty?

      fail!("#{settings.display_name} reaches more than one #{field.one}: #{reached.to_sentence}. Name the #{field.one} with #{field.key}.")
    end

    # Whether the call reads every scope the connection reaches at once, as a listing does when it was named none.
    def every_scope?(environment_row) = @scope.nil? && ConnectionSettings.of(environment_row).several_scopes?

    # What each scope the connection reaches holds, read one scope at a time by the block on a pack of its own, as one
    # snapshot. With several, each of the provider's own resources is marked with its scope (ResourceMap::SCOPE), and a
    # scope that cannot be read is a gap naming kinds, so nothing it held is taken as gone while the others are still
    # read. A connection whose every scope fails, or that reaches one, fails the sweep as before.
    def map_of_scopes(environment_row, kinds:)
      settings = ConnectionSettings.of(environment_row)
      return yield(scoped(scope!(environment_row))) unless settings.several_scopes?

      failures = []
      learn_scope_names(settings)
      snapshots = settings.scopes.map do |each|
        Scopes.marked(yield(scoped(each)), settings, each)
      rescue Integrations::RateLimited
        raise
      rescue Integrations::Error => error
        failures << error
        ResourceMap::Snapshot.new(resources: [], gaps: [ ResourceMap::Gap.new(text: Sentence.join("#{settings.scope_field.one.upcase_first} #{settings.scope_name(each)} could not be read", error), kinds: kinds) ])
      end
      raise failures.first if failures.any? && failures.size == snapshots.size

      ResourceMap::Snapshot.merged(snapshots)
    end

    # Lists the scopes again for their names, which mark what the sweep reads. A listing the token may not make leaves
    # them named by their ids.
    def learn_scope_names(settings)
      settings.scope_options
    rescue Integrations::RateLimited
      raise
    rescue Integrations::Error, NotImplementedError
      nil
    end
    private :learn_scope_names

    # What the block answers for each scope the resources live in, on a pack of that scope's own, as one list.
    def by_scope(environment_row, resources, &)
      Scopes.grouped(ConnectionSettings.of(environment_row), resources).flat_map { |each, group| yield(scoped(each), group) }
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

    # Only what lies within scope (a ResourceMap::Scope), read again after the provider said it changed, as a
    # ResourceMap::Snapshot naming in gone the keys the provider answered not found for. nil means the pack cannot narrow
    # its read to the scope, and the connection is swept in full instead.
    def map_refresh(environment_row, scope)
    end

    # What normal looks like for the given map resources, as ResourceMap::Baseline::Found readings over window. nil means
    # the pack reads no metrics.
    def baselines_of(environment_row, resources, window)
    end
  end
end
