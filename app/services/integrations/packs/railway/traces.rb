module Integrations
  module Packs
    class Railway < NativePack
      # An environment's request traces, as the CLI's railway trace list and get read them (railwayapp/cli,
      # src/gql/queries/strings/Traces.graphql and Trace.graphql, and docs content/docs/cli/trace.md). Railway traces a
      # service once tracing is on for it in that environment, which is a preview feature, and keeps only spans of the
      # environment asked. Railway documents no address for a trace's page, so each answer links to the service.
      module Traces
        SEARCH_TRACES = "search_traces".freeze
        TRACE_LIMIT = 20
        MOST_TRACES = 100
        MOST_SPANS = 200
        TRACE_ID = /\A\h{32}\z/
        ERROR = "ERROR".freeze
        NOT_TRACED = "Railway traces a service only once tracing is on for it in this environment, on its Traces page or with railway trace enable.".freeze

        def self.included(pack)
          pack.tool SEARCH_TRACES,
                    summary: "Searches request traces of a service, or shows one trace's spans.",
                    description: "Request traces of one service in the environment, or of every service when none is named, failed and " \
                                 "slowest first: when each started, how long it took, its root span and path, and how many spans and " \
                                 "errors it has. Filter by text in Railway's search syntax, such as @http.route:/api/users or " \
                                 "@duration:>500. Name a trace by its id to read every span, as a tree, with where the time went and " \
                                 "each error",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "resource" => { "type" => "string", "description" => "A service in the environment, by name or id, as list_resources shows it (optional, every service)" },
                        "environment" => ENVIRONMENT_PARAM,
                        "text" => { "type" => "string", "description" => "Only traces with a span matching this, in Railway's search syntax (optional)" },
                        "trace" => { "type" => "string", "description" => "One trace, by its 32 character id, read with every span (optional)" },
                        "limit" => { "type" => "integer", "description" => "At most this many traces (optional, #{TRACE_LIMIT})" },
                        **Capabilities::RANGE
                      }
                    },
                    read_only: true
        end

        def search_traces(environment_row:, arguments:)
          resource = find_resource(environment_row, arguments["resource"]) if arguments["resource"].present?
          page = resource ? link(environment_row, resource) : project_link(environment_row)
          return one_trace(environment_row, arguments["trace"].to_s.strip, page) if arguments["trace"].present?

          started, ended = Capabilities::Answers.range(arguments)
          limit = [ Capabilities::Answers.limit(arguments, TRACE_LIMIT), MOST_TRACES ].min
          found = api(environment_row).traces("environmentId" => environment(environment_row)["id"], "serviceId" => resource&.dig(:id),
                                              "filter" => arguments["text"].presence, "startDate" => started.utc.iso8601,
                                              "endDate" => ended.utc.iso8601, "limit" => limit)
          what = "#{resource ? resource[:name] : "the #{environment(environment_row)['name']} environment"} from #{started.utc.iso8601} to #{ended.utc.iso8601}"
          return Telemetry.result("No traces of #{what}. #{NOT_TRACED}", link: page) if found.empty?

          rows = found.sort_by { |trace| [ trace["errorCount"].to_i.positive? ? 0 : 1, -trace["durationMs"].to_f ] }.map { |trace| trace_line(trace) }
          Telemetry.result("#{rows.size} traces of #{what}, failed and slowest first. Pass a trace's id as trace to read its spans.\n#{rows.join("\n")}", link: page)
        end

        private

        def one_trace(environment_row, id, page)
          fail! "A trace id is 32 hexadecimal characters, as search_traces lists it." unless id.match?(TRACE_ID)

          spans = api(environment_row).trace(environment(environment_row)["id"], id.downcase, max_spans: MOST_SPANS)
          return Telemetry.result("No trace #{id} in the #{environment(environment_row)['name']} environment. #{NOT_TRACED}", link: page) if spans.empty?

          children = spans.group_by { |span| span["parentSpanId"].presence }
          known = spans.to_set { |span| span["spanId"] }
          roots = spans.select { |span| span["parentSpanId"].blank? || !known.include?(span["parentSpanId"]) }
          lines = roots.sort_by { |span| span["startedAt"].to_s }.flat_map { |span| span_lines(span, children, 0) }
          cut = " Only the first #{MOST_SPANS} spans were read." if spans.size >= MOST_SPANS
          Telemetry.result("Trace #{id}, #{spans.size} spans, oldest first.#{cut}\n#{lines.join("\n")}", link: page)
        end

        def span_lines(span, children, depth)
          failed = ", error#{": #{span['statusMessage']}" if span['statusMessage'].present?}" if span["statusCode"] == ERROR
          line = "#{'  ' * depth}- #{span['name']} (#{span['component']}, #{span['serviceName']}), #{span['durationMs'].to_f.round(1)}ms#{failed}"
          kids = Array(children[span["spanId"]]).sort_by { |child| child["startedAt"].to_s }
          [ line, *kids.flat_map { |child| span_lines(child, children, depth + 1) } ]
        end

        def trace_line(trace)
          root = [ trace["rootSpanName"], trace["rootUrlPath"] ].compact_blank.uniq.join(" ")
          errors = trace["errorCount"].to_i
          [ trace["startedAt"], root, "#{trace['durationMs'].to_f.round(1)}ms", "#{trace['spanCount']} spans", ("#{errors} errors" if errors.positive?),
            "service #{trace['serviceName'].presence || trace['rootServiceName']}", "trace #{trace['traceId']}" ].compact.join(", ")
        end
      end
    end
  end
end
