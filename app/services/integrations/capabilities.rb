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
    HISTORY = "history".freeze
    ROLLBACK = "rollback".freeze
    RESTART = "restart".freeze
    SCALE = "scale".freeze

    RESOURCE_ARG = "resource".freeze
    CONNECTION_ARG = "connection".freeze
    # connection: all asks every connection that can answer, each answer labelled with where it came from.
    ALL = Integration::SLUG_ALL
    # What an observability tool answers by default when the platform that runs a resource could too.
    SIGNALS = [ LOGS, METRICS, TRACES, ERRORS ].freeze
    # app is what the code prints, requests the traffic reaching it, internal the calls between services, cdn what a
    # CDN in front of it served, backup and restore a database's own jobs.
    STREAM_APP = "app".freeze
    STREAM_BUILD = "build".freeze
    LOG_STREAMS = [ STREAM_APP, STREAM_BUILD, *%w[requests internal cdn backup restore] ].freeze
    # The metric names every adapter maps to its provider's own, so a question reads the same whatever answers it.
    # latency_p95 is the time 95% of requests finished within, duration a function's average run, invocations its runs
    # and throttles the runs its provider turned away.
    METRIC_NAMES = %w[
      cpu memory requests errors http_4xx http_5xx cpu_time network_in network_out tcp_connections disk bandwidth latency_p95
      invocations duration throttles
    ].freeze
    DEFAULT_MINUTES = 60
    MAX_MINUTES = 7 * 24 * 60
    # The shared read that runs one of a resource's key checks (ResourceMap::KeyQueries) through a capability.
    KEY_QUERY_TOOL = "run_key_query".freeze
    # The shared read that mines a resource's recent logs for patterns it does not usually print (ResourceMap::LogTemplate).
    LOG_PATTERNS_TOOL = "new_log_patterns".freeze

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
               description: "Log lines of one resource on the map, newest first, from whichever connection runs or watches it. Filter by text " \
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
               description: "Metrics of one resource on the map over time, from whichever connection runs or watches it, with min, average, " \
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
      Spec.new(key: HISTORY, tool_name: "run_history", writes: false, what: "run history",
               description: "Recent runs of one resource on the map, newest first, from whichever connection runs it: a repository's CI " \
                            "runs, or a service's builds and deploys, each with its status, when it started and finished and how long it " \
                            "took, and how long finished ones usually take. Use it to learn how long something usually takes or to follow one run",
               params: { "name" => { "type" => "string", "description" => "Only runs whose workflow, pipeline or kind contains this, such as release or build (optional)" },
                         "run" => { "type" => "string", "description" => "Only this run, by its id, with its jobs or steps where the provider breaks a run down (optional)" },
                         "limit" => LIMIT }, required: []),
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

    # What an adapter answers: the provider tool to run, its own arguments, and how to read its answer back into the
    # shapes every capability returns, or nil when the tool already answers in them.
    Route = Data.define(:tool_name, :arguments, :present) do
      def initialize(present: nil, **) = super
    end

    # A connection that can answer for a resource: one that runs it, or an observability tool that watches it.
    Candidate = Data.define(:resource, :row, :adapter, :observer) do
      def settings = ConnectionSettings.of(row)
    end

    # A connection asked under connection: all that could not answer, and why.
    Refused = Data.define(:environment_row, :reason)

    # A request resolved to one connection: the resource, the row that reaches it, and the provider tool it runs as.
    # fallback is the platform's call to make when the observability tool asked by default has no answer.
    Call = Data.define(:spec, :resource, :environment_row, :tool, :arguments, :present, :fallback) do
      def initialize(fallback: nil, **) = super
      def environment_entry = environment_row.environment

      def scope = environment_row.ability_scope

      def present_result(result) = present ? present.call(result) : result

      # How an agent names the connection, with its environment when the connection is wired per environment.
      def connection = Capabilities.connection_label(environment_row)
    end

    def self.spec(key) = SPECS.fetch(key)

    # What Halon can do through a provider, in a sentence a person reads in its details. A provider without an adapter
    # is still used through its own tools.
    PHRASES = {
      LOGS => "read its logs", METRICS => "read its metrics", DEPLOYS => "see what was deployed", STATUS => "check how a resource stands",
      ERRORS => "read its errors", TRACES => "read its traces", HISTORY => "see how long its runs usually take", ROLLBACK => "roll a resource back", RESTART => "restart a service",
      SCALE => "scale a service"
    }.freeze

    # A provider's pack may say it in its own words (NativePack.halon_sentence), and an adapter says what it answers for
    # (Adapter#subject) and how each capability reads for it (Adapter#phrase).
    def self.halon_sentence(provider, name)
      told = Provider.for(provider).pack&.halon_sentence(name)
      return told if told

      own = "Halon uses #{name}'s own tools that are switched on, in chats and investigations."
      adapter = adapter_for(provider)
      keys = adapter&.capabilities.to_a
      return own if keys.empty?

      "Halon can #{keys.map { |key| adapter.phrase(key) }.to_sentence} for #{adapter.subject(name)}, through the tools that are switched on. " \
        "It also uses #{name}'s other tools that are switched on."
    end

    # The adapter a provider's definition names (Integrations::Provider), or nil.
    def self.adapter_for(provider) = Provider.for(provider).adapter

    # The metric the connection's baselines keep for a capability metric name on a kind of resource, or nil when its
    # provider keeps nothing comparable (Adapter#baseline_metric).
    def self.baseline_metric(environment_row, name, kind) = adapter_for(environment_row.integration.provider)&.baseline_metric(name, kind)

    # Provider tools an adapter answers one to one, which an agent holding the capability is not offered as well.
    def self.wrapped?(tool) = adapter_for(tool.integration.provider)&.wraps?(tool.name) || false

    # The capabilities some connection in the workspace can answer, with the tools they can run as.
    def self.offered(workspace, tools: Integration::Tool.in_workspace(workspace).to_a)
      SPECS.values.filter_map do |spec|
        able = tools.select { |tool| adapter_for(tool.integration.provider)&.runs?(spec.key, tool.name) }
        [ spec, able ] if able.any?
      end
    end

    # The connections whose provider checks addresses from outside, an uptime monitor that answers status for a hostname
    # it checks, region by region. A check from Halon's sandbox sees from one region and names these for the rest.
    def self.outside_checkers(workspace, tools: Integration::Tool.in_workspace(workspace).to_a)
      status = offered(workspace, tools: tools).find { |spec, _able| spec.key == STATUS }
      Array(status&.last).map(&:integration).uniq.select { |integration| adapter_for(integration.provider).observes?(STATUS, ResourceMap::KIND_DOMAIN) }
    end

    # The connections that could answer a capability, as an agent names them: the slug, then the environment's slug
    # when one connection is wired to several.
    def self.connections(tools)
      tools.map(&:integration).uniq.flat_map { |integration| integration.integration_environments.enabled.includes(:environment).map { |row| connection_label(row) } }.uniq
    end

    # The connections an agent may name for a capability, which are every one whose provider answers it, its tools switched on or
    # not, so a connection that holds the resource is never missing from the choice. Asking one whose tool is off answers
    # that it is off (switched_off).
    def self.connection_choices(workspace, spec, tools)
      rows = IntegrationEnvironment.reachable.includes(:integration, :environment).where(integrations: { workspace_id: workspace.id })
                                   .order("integrations.created_at").to_a
      answering = rows.select { |row| adapter_for(row.integration.provider)&.capabilities.to_a.include?(spec.key) }
      (connections(tools) + answering.map { |row| connection_label(row) }).uniq
    end

    def self.connection_label(row)
      wired = row.integration.integration_environments.enabled.count > 1 && row.environment
      wired ? "#{row.integration.slug}/#{row.environment.slug}" : row.integration.slug
    end

    # The resources on the map a connection that holds them can act on with a capability, such as every service some
    # connection can roll back, by name. Only a resource's own holders count, as a person picking one expects.
    def self.actionable(workspace, key)
      adapters = IntegrationEnvironment.reachable.includes(:integration).where(integrations: { workspace_id: workspace.id })
                                       .to_h { |row| [ row.id.to_s, adapter_for(row.integration.provider) ] }.compact
      ResourceMap::Resource.present.where(workspace_id: workspace.id).order(:name)
                           .select(:id, :name, :kind, :provider, :integration_environment_id, :sightings).select do |resource|
        [ resource.integration_environment_id, *resource.sightings.to_h.keys ].compact.map(&:to_s).any? { |id| adapters[id]&.supports?(key, resource.kind) }
      end
    end

    # The provider's own tool a capability runs as, by the capability's tool name, or nil when it is not one.
    def self.provider_tool(provider, tool_name)
      spec = SPECS.values.find { |each| each.tool_name == tool_name.to_s }
      spec && adapter_for(provider)&.tool_for(spec.key)
    end

    # Said where no connection answers a read for a resource, since the provider that holds it may still reach it with the
    # general read its connection offers.
    GENERAL_READ_HINT = " The connection that holds it may still read it with its general read (api_read, or a GET through " \
                        "api_request or execute): find the call in the provider's API reference with use_skill or search_docs.".freeze

    # Names the capabilities and the reads built on them take, so no connection tool is offered under the same name.
    def self.tool_names = [ *SPECS.values.map(&:tool_name), KEY_QUERY_TOOL, LOG_PATTERNS_TOOL ]

    # The tools principal may run for a capability, so a call is routed only to a connection it can use.
    def self.callable(workspace, key, principal)
      resolved = Ability::Resolver.resolve(principal, workspace)
      tools = offered(workspace).find { |spec, _tools| spec.key == key }&.last.to_a
      tools.select { |tool| tool.callable_by?(principal, resolved) }
    end

    def self.schema(spec, connections)
      properties = { RESOURCE_ARG => { "type" => "string", "description" => "The resource, by its name, its provider's id or its id on the resource map, as search_map or get_resource gave it" } }
      if connections.size > 1
        choices = spec.writes ? connections : [ *connections, ALL ]
        properties[CONNECTION_ARG] = { "type" => "string", "enum" => choices,
                                       "description" => "The connection to ask when more than one can answer (optional). Without it, an observability " \
                                                        "tool answers logs, metrics, traces and errors, and the platform that runs the resource " \
                                                        "answers the rest. Follow the team's instructions when they say which to ask.#{" all asks every one." unless spec.writes}" }
      end
      { "type" => "object", "properties" => properties.merge(spec.params), "required" => [ RESOURCE_ARG, *spec.required ] }
    end

    # Finds the resource, the connection that can answer for it, and the provider call to make. Raises Unroutable with
    # words an agent can act on when there is none, or more than one and the request did not say which.
    # tools are the ones the caller may run, every switched on tool when not given. An observability tool is asked only
    # through one of them, so connecting one never takes away a read the platform answers today. The resource is found
    # among those principal may read on the map, so one outside its environments reads as not on the map.
    def self.resolve(workspace, key, given, tools = nil, principal:)
      tools ||= Integration::Tool.in_workspace(workspace).to_a
      spec = spec(key)
      candidates, reference = candidates_for(workspace, spec, given, tools, principal)
      routed(workspace, spec, candidates, given, reference, tools)
    end

    # The call for a read Firefight makes on its own about a resource it picked, such as the daily read of its usual log
    # lines. It is routed as any request is, through every switched on tool, with nobody's reach, since nobody asked.
    # The tool's own recording (Integration::Tool#swept!) is what puts it in the activity log.
    def self.resolve_for(resource, key, given)
      workspace = resource.workspace
      tools = Integration::Tool.in_workspace(workspace).to_a
      spec = spec(key)
      candidates = holders([ resource ], spec, ResourceMap::Resource.present.where(workspace_id: workspace.id))
      candidates += observers(workspace, candidates, [ resource ], spec, tools)
      raise Unroutable, "#{resource.name} is on the map, but no connection offers #{spec.what} for it.#{GENERAL_READ_HINT unless spec.writes}" if candidates.empty?

      routed(workspace, spec, candidates, given.merge(RESOURCE_ARG => resource.id), resource.name, tools)
    end

    def self.routed(workspace, spec, candidates, given, reference, tools)
      chosen = choose(candidates, given, reference, spec)
      call = call_for(workspace, spec, chosen, given, tools)
      return call unless chosen.observer && given[CONNECTION_ARG].blank?

      call.with(fallback: fallback_for(workspace, spec, candidates, chosen, given, tools))
    end

    # The platform that runs the resource, asked when the observability tool chosen for it has no answer. nil when
    # there is none that could be asked.
    def self.fallback_for(workspace, spec, candidates, chosen, given, tools)
      platform = candidates.find { |candidate| !candidate.observer && candidate.resource == chosen.resource }
      platform && call_for(workspace, spec, platform, given, tools)
    rescue Unroutable
      nil
    end

    # Whether an answer says something: not an error, and holding something other than the link back to its page and
    # lists with nothing in them, at any depth. An answer that does not is no answer, so the platform is asked instead.
    def self.definitive?(result)
      return false if result.nil? || (result["isError"] || result[:isError]) == true

      structured = result["structuredContent"] || result[:structuredContent]
      return holds_something?(structured) unless structured.nil?

      texts = Array(result["content"] || result[:content]).filter_map { |part| part["text"] || part[:text] }
      texts.reject { |text| Telemetry.link_line?(text) }.any? { |text| holds_something?(parsed(text)) }
    end

    def self.parsed(text)
      JSON.parse(text)
    rescue JSON::ParserError
      text
    end

    def self.holds_something?(value)
      case value
      when Hash then value.values.any? { |each| holds_something?(each) } && value.values.grep(Array).then { |lists| lists.empty? || lists.any? { |list| holds_something?(list) } }
      when Array then value.any? { |each| holds_something?(each) }
      when String then value.strip.present?
      else !value.nil?
      end
    end

    # What Halon reads when the platform answered in place of the observability tool: why, in the tool's own words
    # when it failed.
    def self.fell_back(call, failure: nil)
      why = failure ? "failed (#{failure.strip})" : "found nothing"
      "#{call.connection} #{why}, so this is from #{call.fallback.connection}."
    end

    # Every connection that can answer for the resource, for connection: all, as a Call or a Refused for each. A change
    # is never made everywhere at once.
    def self.resolve_all(workspace, key, given, tools = nil, principal:)
      tools ||= Integration::Tool.in_workspace(workspace).to_a
      spec = spec(key)
      raise Unroutable, "#{ALL} is only for reading, so a change names one connection." if spec.writes

      candidates, reference = candidates_for(workspace, spec, given, tools, principal)
      one_resource!(candidates, reference)
      candidates.uniq { |candidate| candidate.row.id }.map do |candidate|
        call_for(workspace, spec, candidate, given, tools)
      rescue Unroutable => error
        Refused.new(environment_row: candidate.row, reason: error.message)
      end
    end

    # Why each connection holding the resource keeps no run history Halon can read, in its provider's own note (the
    # registry's history_note), so a watch says what it cannot follow and why.
    def self.history_notes(workspace, reference, principal:)
      return [] if reference.to_s.strip.empty?

      visible = ResourceMap::Resource.visible_to(principal, workspace)
      rows = visible.referenced(workspace, reference.to_s.strip).present.to_a.flat_map(&:holders)
      rows.map(&:integration).uniq.filter_map do |integration|
        entry = IntegrationProvider.find(integration.provider)
        next unless entry && entry.history == IntegrationProvider::HISTORY_NONE

        "#{integration.name} keeps no run history Halon can read. #{entry.history_note}"
      end
    end

    # One connection's answer under connection: all, headed with where it came from.
    def self.headed(environment_row, text) = "From #{connection_label(environment_row)}:\n#{text}"

    def self.candidates_for(workspace, spec, given, tools, principal)
      reference = given[RESOURCE_ARG].to_s.strip
      raise Unroutable, "Say which resource, by its name or its id on the resource map." if reference.empty?

      visible = ResourceMap::Resource.visible_to(principal, workspace)
      named = visible.referenced(workspace, reference).present.to_a
      raise Unroutable, "Nothing on the resource map is called #{reference}. get_resource_map lists what is there." if named.empty?

      candidates = holders(named, spec, visible)
      candidates += observers(workspace, candidates, named, spec, tools)
      raise Unroutable, "#{reference} is on the map, but no connection offers #{spec.what} for it.#{GENERAL_READ_HINT unless spec.writes}" if candidates.empty?

      [ candidates, reference ]
    end

    # The route decides which of the provider's tools runs, so a capability can take a different tool for a different
    # kind of resource (a restart of an app and a reboot of a machine). The capability's usual tool is handed to the
    # route for its parameters. The tool the route names has to be switched on, and an observability tool answers only
    # through one the caller may run, so connecting one never takes away a read the platform answers today.
    def self.call_for(workspace, spec, candidate, given, tools)
      switched_on = Integration::Tool.in_workspace(workspace).where(integration_id: candidate.row.integration_id)
      usual = candidate.adapter.tool_for(spec.key)
      usual_tool = switched_on.find_by(name: usual)
      begin
        route = candidate.adapter.route(spec.key, candidate.resource, given.except(RESOURCE_ARG, CONNECTION_ARG), tool: usual_tool, settings: candidate.settings)
      rescue Unroutable
        raise switched_off(candidate, usual) unless usual_tool

        raise
      end

      tool = route.tool_name == usual ? usual_tool : switched_on.find_by(name: route.tool_name)
      raise switched_off(candidate, route.tool_name) unless tool
      if candidate.observer && tools.none? { |each| each.id == tool.id }
        raise Unroutable, "#{candidate.row.integration.name} would answer this with its #{tool.name} tool, which you may not run."
      end

      arguments = candidate.observer ? route.arguments : Scopes.for_resource(candidate.row, candidate.resource, route.arguments)
      Call.new(spec: spec, resource: candidate.resource, environment_row: candidate.row, tool: tool, arguments: arguments, present: route.present)
    end

    def self.switched_off(candidate, tool_name)
      Unroutable.new("#{candidate.row.integration.name} would answer this with its #{tool_name} tool, which is switched off. " \
                     "An admin can switch it on in Integrations.")
    end

    # Every resource of that name with a connection that holds it and can answer. A hostname is answered by what serves
    # it, one link away, by a link that is a fact, never a suggestion no one confirmed, and only when the caller may read
    # what serves it.
    def self.holders(resources, spec, visible, follow: true)
      found = resources.flat_map do |resource|
        resource.holders.filter_map do |row|
          adapter = adapter_for(row.integration.provider)
          Candidate.new(resource: resource, row: row, adapter: adapter, observer: false) if adapter&.supports?(spec.key, resource.kind)
        end
      end
      return found if found.any? || !follow

      served = ResourceMap::Link.facts.where(from_resource: resources, relation: ResourceMap::RELATION_SERVED_BY, to_resource_id: visible.select(:id))
                                .includes(:to_resource).map(&:to_resource).select { |resource| resource.removed_at.nil? }
      holders(served.uniq, spec, visible, follow: false)
    end

    # The observability tools connected to the workspace, which answer for a resource they watch though another
    # connection runs it, such as Datadog for a service Northflank runs.
    # A row wired to an environment answers only for a resource held in that same environment.
    def self.observers(workspace, holding, named, spec, tools)
      rows = IntegrationEnvironment.reachable.includes(:integration, :environment).where(integrations: { workspace_id: workspace.id }).to_a
      watching = rows.filter_map do |row|
        adapter = adapter_for(row.integration.provider)
        [ row, adapter ] if adapter && tools.any? { |tool| tool.integration_id == row.integration_id && adapter.runs?(spec.key, tool.name) }
      end
      resources = holding.map(&:resource).uniq.presence || named
      resources.flat_map do |resource|
        environments = resource.holders.filter_map(&:catalog_entry_id)
        watching.filter_map do |row, adapter|
          next unless adapter.observes?(spec.key, resource.kind) && adapter.reaches?(ConnectionSettings.of(row), spec.key)
          next if environments.any? && row.catalog_entry_id && environments.exclude?(row.catalog_entry_id)

          Candidate.new(resource: resource, row: row, adapter: adapter, observer: true)
        end
      end
    end

    # One resource on one connection. Two resources of the same name are told apart by their id. Between connections,
    # an observability tool answers logs, metrics, traces and errors by default, and the one that runs the resource
    # answers the rest, so a request never lands somewhere it did not mean and Halon need not choose every time.
    def self.choose(candidates, given, reference, spec)
      connection = given[CONNECTION_ARG]
      unique = candidates.uniq { |candidate| [ candidate.resource.id, candidate.row.id ] }
      if connection.present?
        unique = unique.select { |candidate| connection_label(candidate.row) == connection.to_s || candidate.row.integration.slug == connection.to_s }
        raise Unroutable, "#{connection} cannot answer for #{reference}. Choose connection from: #{labels(candidates).join(', ')}." if unique.empty?
      end
      return unique.first if unique.one?

      one_resource!(unique, reference)
      able = unique.reject { |candidate| candidate.observer && !candidate.adapter.accepts?(spec.key, given, settings: candidate.settings) }
      preferred = able.select { |candidate| candidate.observer == SIGNALS.include?(spec.key) }
      return preferred.first if preferred.one?
      return able.first if able.one?
      if able.empty?
        raise Unroutable, unique.map { |candidate| candidate.adapter.route_refusal(spec.key, candidate.resource, given, settings: candidate.settings) }.compact.join(" ")
      end

      raise Unroutable, "More than one connection can answer for #{reference}. Choose connection from: #{labels(unique).join(', ')}, or #{ALL}."
    end

    # The resources an observability connection answers a capability for, as observers would offer them: every one on
    # the map of a kind it watches that a connection in its workspace holds, and for a connection wired to an
    # environment only those held in that environment. A platform watches nothing.
    def self.watched(environment_row, key)
      adapter = adapter_for(environment_row.integration.provider)
      kinds = adapter&.observed.to_h.fetch(key, [])
      return [] if kinds.empty? || !adapter.reaches?(ConnectionSettings.of(environment_row), key)

      ResourceMap::Resource.present.where(workspace_id: environment_row.integration.workspace_id, kind: kinds).to_a.select do |resource|
        holders = resource.holders
        environments = holders.filter_map(&:catalog_entry_id)
        holders.any? && (environments.empty? || environment_row.catalog_entry_id.nil? || environments.include?(environment_row.catalog_entry_id))
      end
    end

    def self.one_resource!(candidates, reference)
      resources = candidates.map(&:resource).uniq
      return if resources.one?

      named = resources.map do |resource|
        through = candidates.select { |candidate| candidate.resource == resource }.map { |candidate| candidate.row.integration.display_name }.uniq
        "#{resource.kind} #{resource.scoped_name} (map id #{resource.id}, on #{through.to_sentence}, its provider's id #{resource.external_id})"
      end
      rows = labels(candidates)
      choice = rows.size > 1 ? ", or choose connection from: #{rows.join(', ')}" : ""
      raise Unroutable, "More than one resource is called #{reference}: #{named.to_sentence}. Name it by its map id#{choice}."
    end

    def self.labels(candidates) = candidates.map { |candidate| connection_label(candidate.row) }.uniq
    private_class_method :parsed, :holds_something?, :fallback_for, :routed, :candidates_for, :call_for, :switched_off, :holders, :observers, :choose, :one_resource!, :labels
  end
end
