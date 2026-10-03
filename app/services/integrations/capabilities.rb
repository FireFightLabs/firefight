module Integrations
  # One way to ask for the logs, metrics, deploys or status of anything on the resource map, or to roll it back, restart
  # it or scale it, whichever connected provider holds it. A provider's adapter turns each request into a call of one of
  # that provider's own tools, so the call is authorized, approved, ledgered and replayed as that tool's action, exactly
  # as if the agent had called the tool itself. Adding a provider is an adapter, and every caller works with it.
  module Capabilities
    class Unroutable < Integrations::Error; end

    LOGS = "logs".freeze
    METRICS = "metrics".freeze
    DEPLOYS = "deploys".freeze
    STATUS = "status".freeze
    ERRORS = "errors".freeze
    TRACES = "traces".freeze
    ROLLBACK = "rollback".freeze
    RESTART = "restart".freeze
    SCALE = "scale".freeze

    RESOURCE_ARG = "resource".freeze
    CONNECTION_ARG = "connection".freeze
    # app is what the code prints, requests the traffic reaching it, internal the calls between services, cdn what a
    # CDN in front of it served, backup and restore a database's own jobs.
    LOG_STREAMS = %w[app build requests internal cdn backup restore].freeze
    # The metric names every adapter maps to its provider's own, so a question reads the same whatever answers it.
    METRIC_NAMES = %w[cpu memory requests errors http_4xx http_5xx cpu_time network_in network_out tcp_connections disk bandwidth].freeze
    DEFAULT_MINUTES = 60
    MAX_MINUTES = 7 * 24 * 60

    RANGE = {
      "minutes" => { "type" => "integer", "description" => "How far back from now, in minutes (optional, #{DEFAULT_MINUTES})" },
      "start" => { "type" => "string", "description" => "Start of the range as an ISO 8601 time, instead of minutes (optional)" },
      "end" => { "type" => "string", "description" => "End of the range as an ISO 8601 time (optional, now)" }
    }.freeze
    LIMIT = { "type" => "integer", "description" => "At most this many (optional)" }.freeze

    # What each capability is called by, what it asks, and whether it changes anything. params are on top of the
    # resource and the connection every capability takes.
    Spec = Data.define(:key, :tool_name, :writes, :what, :description, :params, :required)

    SPECS = [
      Spec.new(key: LOGS, tool_name: "search_logs", writes: false, what: "logs",
               description: "Log lines of one resource on the map, newest first, from whichever connection runs it. Filter by text " \
                            "or a regular expression. stream picks what the app prints (app, the default), its builds, or the " \
                            "requests reaching it, where the provider keeps them",
               params: {
                 "text" => { "type" => "string", "description" => "Only lines containing this text (optional)" },
                 "regex" => { "type" => "string", "description" => "Only lines matching this regular expression (optional)" },
                 "exclude" => { "type" => "string", "description" => "Leave out lines containing this text (optional)" },
                 "stream" => { "type" => "string", "enum" => LOG_STREAMS,
                               "description" => "Which logs: app (what the code prints), build, requests (traffic reaching it), internal (calls between services), cdn, backup or restore (optional, app)" },
                 "limit" => LIMIT, **RANGE
               }, required: []),
      Spec.new(key: METRICS, tool_name: "query_metrics", writes: false, what: "metrics",
               description: "Metrics of one resource on the map over time, from whichever connection runs it, with min, average, " \
                            "max and latest for each. The person sees each metric as a chart. A metric the provider does not " \
                            "keep for that resource is named as missing",
               params: {
                 "metrics" => { "type" => "array", "items" => { "type" => "string", "enum" => METRIC_NAMES },
                                "description" => "Which metrics (optional, the resource's usual ones)" },
                 **RANGE
               }, required: []),
      Spec.new(key: DEPLOYS, tool_name: "recent_deploys", writes: false, what: "deploys",
               description: "What went out to one resource on the map, newest first: when, which commit or version, by whom and " \
                            "why, with the id rollback takes. Use it to see what changed before something broke",
               params: { "limit" => LIMIT }, required: []),
      Spec.new(key: STATUS, tool_name: "resource_status", writes: false, what: "status",
               description: "How one resource on the map is set up and how it stands now, read live from whichever connection " \
                            "runs it: its state, size, what it runs and its health checks",
               params: {}, required: []),
      Spec.new(key: ERRORS, tool_name: "search_errors", writes: false, what: "errors",
               description: "Errors one resource on the map raised, newest first, grouped by kind with how often each happened",
               params: { "text" => { "type" => "string", "description" => "Only errors containing this text (optional)" }, "limit" => LIMIT, **RANGE },
               required: []),
      Spec.new(key: TRACES, tool_name: "search_traces", writes: false, what: "traces",
               description: "Request traces through one resource on the map, slowest or failed first, with where the time went",
               params: { "text" => { "type" => "string", "description" => "Only traces whose route or span contains this text (optional)" },
                         "limit" => LIMIT, **RANGE },
               required: []),
      Spec.new(key: ROLLBACK, tool_name: "rollback", writes: true, what: "a rollback",
               description: "Put one resource on the map back on an earlier build or version, through whichever connection runs it",
               params: { "to" => { "type" => "string", "description" => "The build, version or deployment to go back to, by the id the provider gives it in recent_deploys or its build list" } },
               required: [ "to" ]),
      Spec.new(key: RESTART, tool_name: "restart", writes: true, what: "a restart",
               description: "Restart one resource on the map, through whichever connection runs it, for one stuck in a bad state " \
                            "while its code is fine",
               params: {}, required: []),
      Spec.new(key: SCALE, tool_name: "scale", writes: true, what: "scaling",
               description: "Set how many instances one resource on the map runs, through whichever connection runs it",
               params: { "instances" => { "type" => "integer", "description" => "How many instances to run" } },
               required: [ "instances" ])
    ].index_by(&:key).freeze

    ADAPTERS = {
      Packs::Northflank::PROVIDER_KEY => "Integrations::Capabilities::Northflank",
      MapReaders::Cloudflare::PROVIDER => "Integrations::Capabilities::Cloudflare"
    }.freeze

    # What an adapter answers: the provider tool to run, its own arguments, and how to read its answer back into the
    # shapes every capability returns, or nil when the tool already answers in them.
    Route = Data.define(:tool_name, :arguments, :present) do
      def initialize(present: nil, **) = super
    end

    # A request resolved to one connection: the resource, the row that reaches it, and the provider tool it runs as.
    Call = Data.define(:spec, :resource, :environment_row, :tool, :arguments, :present) do
      def environment_entry = environment_row.environment

      def scope = environment_row.catalog_entry_id ? { "environment" => environment_row.catalog_entry_id } : {}

      def present_result(result) = present ? present.call(result) : result

      # How an agent names the connection, with its environment when the connection is wired per environment.
      def connection = Capabilities.connection_label(environment_row)
    end

    def self.spec(key) = SPECS.fetch(key)

    def self.adapter_for(provider) = ADAPTERS[provider.to_s]&.constantize

    # Provider tools an adapter answers one to one, which an agent holding the capability is not offered as well.
    def self.wrapped?(tool) = adapter_for(tool.integration.provider)&.wraps?(tool.name) || false

    # The capabilities some connection in the workspace can answer, with the tools they can run as.
    def self.offered(workspace, tools: Integration::Tool.in_workspace(workspace).to_a)
      SPECS.values.filter_map do |spec|
        able = tools.select { |tool| adapter_for(tool.integration.provider)&.runs?(spec.key, tool.name) }
        [ spec, able ] if able.any?
      end
    end

    # The connections that could answer a capability, as an agent names them: the slug, then the environment's slug
    # when one connection is wired to several.
    def self.connections(tools)
      tools.map(&:integration).uniq.flat_map { |integration| integration.integration_environments.enabled.includes(:environment).map { |row| connection_label(row) } }.uniq
    end

    def self.connection_label(row)
      wired = row.integration.integration_environments.enabled.count > 1 && row.environment
      wired ? "#{row.integration.slug}/#{row.environment.slug}" : row.integration.slug
    end

    # The provider's own tool a capability runs as, by the capability's tool name, or nil when it is not one.
    def self.provider_tool(provider, tool_name)
      spec = SPECS.values.find { |each| each.tool_name == tool_name.to_s }
      spec && adapter_for(provider)&.const_get(:TOOLS)&.[](spec.key)
    end

    # Names the capabilities take, so no connection tool is offered under the same name.
    def self.tool_names = SPECS.values.map(&:tool_name)

    def self.schema(spec, connections)
      properties = { RESOURCE_ARG => { "type" => "string", "description" => "The resource, by its name or id on the resource map" } }
      if connections.size > 1
        properties[CONNECTION_ARG] = { "type" => "string", "enum" => connections,
                                       "description" => "The connection to ask, when more than one holds the resource (optional)" }
      end
      { "type" => "object", "properties" => properties.merge(spec.params), "required" => [ RESOURCE_ARG, *spec.required ] }
    end

    # Finds the resource, the connection that holds it and can answer, and the provider call to make. Raises Unroutable
    # with words an agent can act on when there is none, or more than one and the request did not say which.
    def self.resolve(workspace, key, given)
      spec = spec(key)
      reference = given[RESOURCE_ARG].to_s.strip
      raise Unroutable, "Say which resource, by its name or id on the resource map." if reference.empty?

      named = ResourceMap::Resource.named(workspace, reference).present.to_a
      raise Unroutable, "Nothing on the resource map is called #{reference}. get_resource_map lists what is there." if named.empty?

      candidates = holders(named, spec)
      raise Unroutable, "#{reference} is on the map, but no connection that holds it offers #{spec.what} for it." if candidates.empty?

      resource, row, adapter = choose(candidates, given[CONNECTION_ARG], reference)
      route = adapter.route(spec.key, resource, given.except(RESOURCE_ARG, CONNECTION_ARG))
      tool = Integration::Tool.in_workspace(workspace).find_by(integration_id: row.integration_id, name: route.tool_name)
      unless tool
        raise Unroutable, "#{row.integration.name} would answer this with its #{route.tool_name} tool, which is switched off. " \
                          "An admin can switch it on in Integrations."
      end

      Call.new(spec: spec, resource: resource, environment_row: row, tool: tool, arguments: route.arguments, present: route.present)
    end

    # Every resource of that name with a connection that holds it and can answer, as [resource, row, adapter]. A
    # hostname is answered by what serves it, one link away, by a link that is a fact, never a suggestion no one
    # confirmed.
    def self.holders(resources, spec, follow: true)
      found = resources.flat_map do |resource|
        resource.holders.filter_map do |row|
          adapter = adapter_for(row.integration.provider)
          [ resource, row, adapter ] if adapter&.supports?(spec.key, resource.kind)
        end
      end
      return found if found.any? || !follow

      served = ResourceMap::Link.facts.where(from_resource: resources, relation: ResourceMap::RELATION_SERVED_BY).includes(:to_resource)
                                .map(&:to_resource).select { |resource| resource.removed_at.nil? }
      holders(served.uniq, spec, follow: false)
    end

    # One resource on one connection. Two resources of the same name are told apart by their id, two connections by
    # connection, so a request never lands on a resource it did not mean.
    def self.choose(candidates, connection, reference)
      unique = candidates.uniq { |resource, row, _adapter| [ resource.id, row.id ] }
      if connection.present?
        unique = unique.select { |_resource, row, _adapter| connection_label(row) == connection.to_s || row.integration.slug == connection.to_s }
        raise Unroutable, "#{connection} does not hold #{reference}. Choose connection from: #{labels(candidates).join(', ')}." if unique.empty?
      end
      return unique.first if unique.one?

      resources = unique.map(&:first).uniq
      if resources.size > 1
        named = resources.map { |resource| "#{resource.kind} #{resource.name} (id #{resource.external_id}, #{resource.provider})" }
        rows = labels(unique)
        choice = rows.size > 1 ? ", or choose connection from: #{rows.join(', ')}" : ""
        raise Unroutable, "More than one resource is called #{reference}: #{named.join('; ')}. Name it by its id#{choice}."
      end

      raise Unroutable, "More than one connection holds #{reference}. Choose connection from: #{labels(unique).join(', ')}."
    end

    def self.labels(candidates) = candidates.map { |_resource, row, _adapter| connection_label(row) }.uniq
    private_class_method :holders, :choose, :labels
  end
end
