module Integrations
  # The gateway has already said yes before call is reached. This only executes.
  class McpExecutor
    # A remote server keeps its own state, so the run's box key means nothing to it, and it says nothing until it
    # answers, so nobody hears progress from it.
    def self.call(tool:, environment_row:, arguments:, box_key: nil, progress: nil)
      result = client_for(tool.integration, environment_row)
               .call_tool(name: tool.remote_name, arguments: arguments)
      kept = Redactions.apply(ToolResult.normalize(result), fields: Provider.for(tool.integration.provider).redacted_fields)
      SourceLinks.attach(kept, settings: ConnectionSettings.of(environment_row), tool_name: tool.name, arguments: arguments)
    end

    # Names are sanitized into action-key-safe form, spec keeps the server's own name for the call.
    def self.tool_definitions(integration)
      environment_row = integration.resolve_environment(nil) || integration.integration_environments.enabled.first

      client_for(integration, environment_row).tools_list.map do |remote|
        ToolDefinition.new(
          name: local_name(remote["name"]),
          description: remote["description"],
          params_schema: remote["inputSchema"] || {},
          read_only: remote.dig("annotations", "readOnlyHint") == true,
          spec: { "tool_name" => remote["name"] }
        )
      end
    end

    # The name Firefight gives a server's tool, such as query_logs for a tool the server calls query-logs.
    def self.local_name(remote_name) = remote_name.to_s.downcase.gsub(/[^a-z0-9_.]/, "_")

    # A server that answers a ping may still not reach the account behind it, so a provider with a health probe is also
    # asked through its own tools, only those switched on, each call recorded under the health check. What the
    # probe learned is kept on the row, for the provider's adapter and links to read.
    def self.check_health!(environment_row)
      client = client_for(environment_row.integration, environment_row)
      client.ping
      learned = reader(environment_row, :health_probe, :checked!, client)&.check!
      environment_row.store_learned!(learned) if learned
    end

    # Whether the health check reads through the connection's tools, so switching one on or off checks it again.
    def self.checks_through_tools?(integration) = Provider.for(integration.provider).health_probe.present?

    # A remote server lists tools, not what it reaches, so a provider goes on the map through the reader its definition
    # names, which calls only the tools that are switched on. Without a reader the connection puts nothing on the map.
    # How often a reader is swept on the hourly schedule, when it says. Sync now reads it at once whatever this says.
    DEFAULT_MAP_EVERY = 1.hour

    def self.map_every(integration)
      reader = Provider.for(integration.provider).map_reader
      reader&.const_defined?(:EVERY, false) ? reader::EVERY : DEFAULT_MAP_EVERY
    end

    def self.map_of(environment_row) = reader(environment_row, :map_reader, :swept!)&.map

    # A re-read of one scope after the provider said something there changed, through the same reader and switched on
    # tools, recorded under the map sweep. A reader narrows its read when its map takes scope:, and answers a Snapshot
    # naming in gone what the provider answered not found for. nil when it cannot narrow, so the connection is swept in
    # full instead.
    def self.map_refresh(environment_row, scope)
      return unless narrows?(Provider.for(environment_row.integration.provider).map_reader)

      reader(environment_row, :map_reader, :swept!).map(scope: scope)
    end

    # The provider's map reader for its live updates (MapEventSource#poll) to read the provider's change log with its own
    # fixed reads, through the same switched on tools and recorded under the map sweep, as the sweep's reads are.
    def self.map_events_reader(environment_row) = reader(environment_row, :map_reader, :swept!)

    def self.narrows?(reader) = reader.present? && reader.instance_method(:map).parameters.any? { |_type, name| name == :scope }

    # What normal looks like, through the baseline reader the provider's definition names, with its own fixed reads and
    # only the tools that are switched on, each call recorded under the map sweep. Without one there are no baselines.
    def self.baselines_of(environment_row, resources, window)
      reader(environment_row, :baseline_reader, :swept!)&.baselines(resources, window)
    end

    # The provider's reader of that part, made to call the connection's switched on tools recorded the way recording
    # says, or nil when the provider has none.
    def self.reader(environment_row, part, recording, client = nil)
      integration = environment_row.integration
      reader = Provider.for(integration.provider).public_send(part)
      return unless reader

      client ||= client_for(integration, environment_row)
      tools = integration.tools.enabled.available.index_by(&:name)
      reader.new(ConnectionSettings.of(environment_row), tools) do |name, arguments, reads = nil|
        tool = tools[name]
        tool&.public_send(recording, arguments, reads) { client.call_tool(name: tool.remote_name, arguments: arguments) }
      end
    end

    def self.client_for(integration, environment_row)
      McpClient.new(server_url: integration.server_url, headers: Credentials.headers_for(environment_row))
    end
    private_class_method :client_for, :reader, :narrows?
  end
end
