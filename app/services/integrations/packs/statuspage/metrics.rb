module Integrations
  module Packs
    class Statuspage < NativePack
      # A page's system metrics, the charts it shows customers, and the providers they come from. A provider that pulls
      # from Datadog, New Relic, Librato or Pingdom holds that service's keys, which would pass through the call and the
      # activity log, so only a Self provider, which holds none and takes data sent to it, is made here. Its metrics and
      # every other provider's are read, renamed and removed alike.
      module Metrics
        METRIC = { "type" => "string", "description" => "The metric, by its id or name, as list_metrics shows it" }.freeze
        PROVIDER = { "type" => "string", "description" => "The metrics provider's id, as list_metrics_providers shows it" }.freeze
        POINTS_LIMIT = 3_000

        def self.included(pack)
          pack.tool :list_metrics_providers,
                    summary: "Lists the sources a status page's system metrics come from, such as Datadog or Pingdom.",
                    description: "The providers a page's system metrics come from, each with its id and kind, such as Self, Datadog or Pingdom",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
                    read_only: true

          pack.tool :list_metrics,
                    summary: "Lists the system metric charts a status page shows customers.",
                    description: "A page's system metrics, the charts it shows customers, each with its id, its provider, what it reads " \
                                 "and whether it is shown",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "provider" => PROVIDER.merge("description" => "Only this provider's (optional)") } },
                    read_only: true

          pack.tool :create_metrics_provider,
                    summary: "Adds a metrics source to a status page that charts readings sent to it.",
                    description: "Add a Self metrics provider to a page, whose metrics take the data sent to them with add_metric_data. " \
                                 "A provider that pulls from another service is added in Statuspage, since it holds that service's keys",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
                    read_only: false

          pack.tool :update_metrics_provider,
                    summary: "Changes the address a Datadog or New Relic metrics source reads from.",
                    description: "Change the address a metrics provider reads from, for a Datadog or New Relic provider",
                    params_schema: {
                      "type" => "object",
                      "properties" => { "page" => PAGE, "provider" => PROVIDER, "metric_base_uri" => { "type" => "string", "description" => "The address it reads metrics from" } },
                      "required" => %w[provider metric_base_uri]
                    },
                    read_only: false

          pack.tool :delete_metrics_provider,
                    summary: "Removes a metrics source and its metrics from a status page.",
                    description: "Remove a metrics provider and its metrics from a page",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "provider" => PROVIDER }, "required" => [ "provider" ] },
                    read_only: false

          pack.tool :create_metric,
                    summary: "Adds a metric chart that customers see on a status page.",
                    description: "Add a metric, a chart customers see, to a metrics provider",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "page" => PAGE, "provider" => PROVIDER,
                        "name" => { "type" => "string", "description" => "Its name on the page" },
                        "metric_identifier" => { "type" => "string", "description" => "What the provider reads it by, for a provider that pulls (optional)" },
                        "transform" => { "type" => "string", "enum" => StatuspageApi::METRIC_TRANSFORMS, "description" => "How readings are combined (optional)" },
                        "suffix" => { "type" => "string", "description" => "Its unit on the chart, such as ms (optional)" },
                        "decimal_places" => { "type" => "integer", "description" => "Decimal places shown (optional)" },
                        "y_axis_min" => { "type" => "integer", "description" => "The lowest value on the chart (optional)" },
                        "y_axis_max" => { "type" => "integer", "description" => "The highest value on the chart (optional)" },
                        "y_axis_hidden" => { "type" => "boolean", "description" => "Hide the values on the axis (optional)" },
                        "display" => { "type" => "boolean", "description" => "Show it on the page (optional)" },
                        "tooltip_description" => { "type" => "string", "description" => "What it measures, shown on hover (optional)" }
                      },
                      "required" => %w[provider name]
                    },
                    read_only: false

          pack.tool :update_metric,
                    summary: "Renames a status page metric or changes what it reads.",
                    description: "Rename a metric or change what its provider reads it by",
                    params_schema: {
                      "type" => "object",
                      "properties" => { "page" => PAGE, "metric" => METRIC, "name" => { "type" => "string", "description" => "Its new name (optional)" },
                                        "metric_identifier" => { "type" => "string", "description" => "What the provider reads it by (optional)" } },
                      "required" => [ "metric" ]
                    },
                    read_only: false

          pack.tool :delete_metric,
                    summary: "Deletes a status page metric and its data.",
                    description: "Remove a metric and its data from a page",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "metric" => METRIC }, "required" => [ "metric" ] },
                    read_only: false

          pack.tool :add_metric_data,
                    summary: "Sends new readings to a status page metric chart.",
                    description: "Send readings to a metric of a Self provider, which its chart then shows",
                    params_schema: {
                      "type" => "object",
                      "properties" => {
                        "page" => PAGE, "metric" => METRIC,
                        "points" => {
                          "type" => "array",
                          "items" => { "type" => "object", "properties" => { "at" => { "type" => "string", "description" => "When, as an ISO 8601 time" },
                                                                             "value" => { "type" => "number", "description" => "The reading" } },
                                       "required" => %w[at value] },
                          "description" => "The readings, at most #{POINTS_LIMIT}"
                        }
                      },
                      "required" => %w[metric points]
                    },
                    read_only: false

          pack.tool :reset_metric_data,
                    summary: "Clears every reading of a status page metric, emptying its chart.",
                    description: "Delete every reading of a metric, which empties its chart",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "metric" => METRIC }, "required" => [ "metric" ] },
                    read_only: false
        end

        def list_metrics_providers(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          providers = api(environment_row).metrics_providers(page["id"]).items
          return Telemetry.result("#{page['name']} has no metrics providers.", link: page_link(page)) if providers.empty?

          rows = providers.map { |provider| [ "#{provider['type']} (id #{provider['id']})", ("reads #{provider['metric_base_uri']}" if provider["metric_base_uri"].present?) ].compact.join(", ") }
          Telemetry.result("Metrics providers on #{page['name']}:\n#{rows.join("\n")}", link: page_link(page))
        end

        def list_metrics(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          provider = arguments["provider"].to_s.strip
          metrics = provider.present? ? api(environment_row).provider_metrics(page["id"], provider).items : all_metrics(environment_row, page)
          return Telemetry.result("No metrics on #{page['name']}#{" from provider #{provider}" if provider.present?}.", link: page_link(page)) if metrics.empty?

          rows = metrics.map do |metric|
            [ "#{metric['name']} (id #{metric['id']})", ("provider #{metric['metrics_provider_id']}" if metric["metrics_provider_id"]),
              ("reads #{metric['metric_identifier']}" if metric["metric_identifier"].present?), ("unit #{metric['suffix']}" if metric["suffix"].present?),
              (metric["display"] == false ? "hidden" : "shown"), ("last data #{metric['last_fetched_at']}" if metric["last_fetched_at"]) ].compact.join(", ")
          end
          Telemetry.result("Metrics on #{page['name']}:\n#{rows.join("\n")}", link: page_link(page))
        end

        def create_metrics_provider(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          made = api(environment_row).create_metrics_provider(page["id"], "type" => StatuspageApi::SELF_PROVIDER)
          Telemetry.result("Statuspage added a Self metrics provider (id #{made['id']}) to #{page['name']}.", link: page_link(page))
        end

        def update_metrics_provider(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          id = metrics_provider_id(arguments)
          api(environment_row).update_metrics_provider(page["id"], id, "metric_base_uri" => required(arguments, "metric_base_uri"))
          Telemetry.result("Statuspage changed where metrics provider #{id} reads from.", link: page_link(page))
        end

        def delete_metrics_provider(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          id = metrics_provider_id(arguments)
          api(environment_row).delete_metrics_provider(page["id"], id)
          Telemetry.result("Statuspage removed metrics provider #{id} and its metrics from #{page['name']}.", link: page_link(page))
        end

        def create_metric(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          metric = arguments.slice("metric_identifier", "suffix", "tooltip_description").transform_values { |value| value.to_s.strip.presence }
                            .merge("name" => required(arguments, "name"), "transform" => choice(arguments["transform"], StatuspageApi::METRIC_TRANSFORMS, "transform"))
                            .merge(arguments.slice("decimal_places", "y_axis_min", "y_axis_max").select { |_key, value| value.is_a?(Integer) })
                            .merge(arguments.slice("y_axis_hidden", "display").select { |_key, value| [ true, false ].include?(value) }).compact
          made = api(environment_row).create_metric(page["id"], metrics_provider_id(arguments), metric)
          Telemetry.result("Statuspage added metric #{made['name'] || metric['name']} (id #{made['id']}) to #{page['name']}.", link: page_link(page))
        end

        def update_metric(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          metric = metric_of(environment_row, page, arguments["metric"])
          change = { "name" => arguments["name"].to_s.strip.presence, "metric_identifier" => arguments["metric_identifier"].to_s.strip.presence }.compact
          fail! "Name what to change: name or metric_identifier." if change.empty?

          made = api(environment_row).update_metric(page["id"], metric["id"], change)
          Telemetry.result("Statuspage changed metric #{made['name'] || metric['name']} on #{page['name']}.", link: page_link(page))
        end

        def delete_metric(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          metric = metric_of(environment_row, page, arguments["metric"])
          api(environment_row).delete_metric(page["id"], metric["id"])
          Telemetry.result("Statuspage removed metric #{metric['name']} from #{page['name']}.", link: page_link(page))
        end

        def add_metric_data(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          metric = metric_of(environment_row, page, arguments["metric"])
          points = Array(arguments["points"]).map do |point|
            given = point.to_h.stringify_keys
            fail! "Each point has a value that is a number." unless given["value"].is_a?(Numeric)

            { "timestamp" => time_of(given["at"], "at").to_i, "value" => given["value"] }
          end
          fail! "Give at least one point." if points.empty?
          fail! "Send at most #{POINTS_LIMIT} points at a time." if points.size > POINTS_LIMIT

          api(environment_row).add_metric_data(page["id"], { metric["id"] => points })
          Telemetry.result("Statuspage took #{points.size} #{points.one? ? 'reading' : 'readings'} for #{metric['name']} on #{page['name']}.", link: page_link(page))
        end

        def reset_metric_data(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          metric = metric_of(environment_row, page, arguments["metric"])
          api(environment_row).reset_metric_data(page["id"], metric["id"])
          Telemetry.result("Statuspage deleted every reading of #{metric['name']} on #{page['name']}.", link: page_link(page))
        end

        private

        def all_metrics(environment_row, page) = (@metrics ||= {})[page["id"]] ||= api(environment_row).metrics(page["id"]).items

        def metric_of(environment_row, page, wanted)
          wanted = wanted.to_s.strip
          fail! "Name the metric by its id or name." if wanted.empty?

          found = all_metrics(environment_row, page)
          found.find { |metric| metric["id"] == wanted } || found.find { |metric| metric["name"].to_s.casecmp?(wanted) } ||
            fail!("#{page['name']} has no metric #{wanted}. list_metrics shows them.")
        end

        def metrics_provider_id(arguments) = arguments["provider"].to_s.strip.presence || fail!("Name the metrics provider by its id, as list_metrics_providers shows it.")
      end
    end
  end
end
