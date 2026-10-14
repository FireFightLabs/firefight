module Integrations
  module Packs
    class Instatus < NativePack
      # What else a page holds beside incidents and maintenance: the metrics charted on it, the general notices shown on
      # it, the outages recorded on its components' uptime bars, and the teammates who manage it.
      module PageContent
        METRIC = { "type" => "string", "description" => "The metric, by its id or name, as list_metrics shows it" }.freeze
        NOTICE = { "type" => "string", "description" => "The notice's id, as list_notices shows it" }.freeze
        OUTAGE = { "type" => "string", "description" => "The outage's id, as list_outages shows it" }.freeze
        POINTS_LIMIT = 3_000
        POINTS_SHOWN = 20
        OUTAGE_STATUSES = InstatusApi::COMPONENT_STATUSES - %w[OPERATIONAL].freeze

        def self.included(pack)
          pack.tool :list_metrics,
                    description: "A page's metrics, the charts it shows customers, each with its id, unit and when it last had data",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
                    read_only: true

          pack.tool :get_metric,
                    description: "One metric with its latest readings",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "metric" => METRIC }, "required" => [ "metric" ] },
                    read_only: true

          pack.tool :list_notices,
                    description: "A page's general notices, the banners it shows apart from incidents and maintenance",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
                    read_only: true

          pack.tool :list_outages,
                    description: "The outages recorded on a page's components, each with its id, component, status, when it ran and its incident",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
                    read_only: true

          pack.tool :list_teammates,
                    description: "The people who manage a page in Instatus, each with their member id and email",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
                    read_only: true

          pack.tool :create_metric,
                    description: "Add a metric, a chart customers see, which add_metric_data fills",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "name" => { "type" => "string", "description" => "Its name" },
                      "suffix" => { "type" => "string", "description" => "Its unit, such as ms (optional)" }
                    }, "required" => [ "name" ] },
                    read_only: false

          pack.tool :update_metric,
                    description: "Rename a metric or change its unit",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "metric" => METRIC, "name" => { "type" => "string", "description" => "A new name (optional)" },
                      "suffix" => { "type" => "string", "description" => "A new unit (optional)" }
                    }, "required" => [ "metric" ] },
                    read_only: false

          pack.tool :delete_metric,
                    description: "Remove a metric and its readings from a page",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "metric" => METRIC }, "required" => [ "metric" ] },
                    read_only: false

          pack.tool :add_metric_data,
                    description: "Send readings to a metric, which its chart then shows",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "metric" => METRIC,
                      "points" => {
                        "type" => "array",
                        "items" => { "type" => "object", "properties" => { "at" => { "type" => "string", "description" => "When, as an ISO 8601 time" },
                                                                           "value" => { "type" => "number", "description" => "The reading" } },
                                     "required" => %w[at value] },
                        "description" => "The readings, at most #{POINTS_LIMIT}"
                      }
                    }, "required" => %w[metric points] },
                    read_only: false

          pack.tool :delete_metric_data,
                    description: "Delete every reading of a metric, which empties its chart",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "metric" => METRIC }, "required" => [ "metric" ] },
                    read_only: false

          pack.tool :create_notice,
                    description: "Show a general notice on a page, a banner apart from incidents and maintenance, such as planned changes",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "name" => { "type" => "string", "description" => "Its title" },
                      "message" => { "type" => "string", "description" => "What it says, HTML allowed (optional)" },
                      "collapsed" => { "type" => "boolean", "description" => "Show it collapsed (optional, false)" },
                      "notify" => NOTIFY
                    }, "required" => %w[name notify] },
                    read_only: false

          pack.tool :update_notice,
                    description: "Change a general notice's title, words, or whether it shows collapsed",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "notice" => NOTICE, "name" => { "type" => "string", "description" => "A new title (optional)" },
                      "message" => { "type" => "string", "description" => "New words (optional)" },
                      "collapsed" => { "type" => "boolean", "description" => "Show it collapsed (optional)" }
                    }, "required" => [ "notice" ] },
                    read_only: false

          pack.tool :delete_notice,
                    description: "Take a general notice off a page",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "notice" => NOTICE }, "required" => [ "notice" ] },
                    read_only: false

          pack.tool :create_outage,
                    description: "Record an outage on a component's uptime bar, such as one that happened without an incident",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "component" => COMPONENT,
                      "status" => { "type" => "string", "enum" => OUTAGE_STATUSES, "description" => "How bad it was" },
                      "from" => WHEN.("When it started"), "to" => WHEN.("When it ended (optional)")
                    }, "required" => %w[component status from] },
                    read_only: false

          pack.tool :update_outage,
                    description: "Change an outage's status or when it started or ended",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "outage" => OUTAGE,
                      "status" => { "type" => "string", "enum" => OUTAGE_STATUSES, "description" => "How bad it was (optional)" },
                      "from" => WHEN.("When it started (optional)"), "to" => WHEN.("When it ended (optional)")
                    }, "required" => [ "outage" ] },
                    read_only: false

          pack.tool :delete_outage,
                    description: "Remove an outage from a component's uptime bar",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "outage" => OUTAGE }, "required" => [ "outage" ] },
                    read_only: false

          pack.tool :add_teammate,
                    description: "Invite someone by email to manage a page in Instatus",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "email" => { "type" => "string", "description" => "Their email" } }, "required" => [ "email" ] },
                    read_only: false

          pack.tool :remove_teammate,
                    description: "Take away someone's access to manage a page in Instatus",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "member" => { "type" => "string", "description" => "Their member id or email, as list_teammates shows it" }
                    }, "required" => [ "member" ] },
                    read_only: false
        end

        def list_metrics(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          metrics = all_metrics(environment_row, page)
          return Telemetry.result("#{page['name']} has no metrics.", link: page_link(page)) if metrics.empty?

          rows = metrics.map do |metric|
            [ "#{metric_name(metric)} (id #{metric['id']})", ("unit #{metric['suffix']}" if metric["suffix"].present?), (metric["active"] == false ? "inactive" : nil),
              ("last data #{Time.at(metric['lastDataAt'] / 1000).utc.iso8601}" if metric["lastDataAt"].is_a?(Numeric)) ].compact.join(", ")
          end
          Telemetry.result("Metrics on #{page['name']}:\n#{rows.join("\n")}", link: page_link(page))
        end

        def get_metric(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          metric = api(environment_row).metric(page["id"], metric_of(environment_row, page, arguments["metric"])["id"])
          points = Array(metric["data"]).last(POINTS_SHOWN).map { |point| "#{Time.at(point['timestamp'].to_i / 1000).utc.iso8601} #{point['value']}#{metric['suffix']}" }
          Telemetry.result([ "#{metric_name(metric)} (id #{metric['id']})#{", unit #{metric['suffix']}" if metric['suffix'].present?}",
                             (points.any? ? "Latest readings:\n#{points.join("\n")}" : "No readings yet.") ].join("\n"), link: page_link(page))
        end

        def list_notices(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          notices = api(environment_row).notices(page["id"]).items
          return Telemetry.result("#{page['name']} shows no general notices.", link: page_link(page)) if notices.empty?

          rows = notices.map { |notice| [ "#{notice['name']} (id #{notice['id']})", ("collapsed" if notice["isCollapsed"]), "since #{notice['createdAt']}", notice["message"].to_s.squish.truncate(200).presence ].compact.join(", ") }
          Telemetry.result("General notices on #{page['name']}:\n#{rows.join("\n")}", link: page_link(page))
        end

        def list_outages(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          outages = api(environment_row).outages(page["id"]).items
          return Telemetry.result("#{page['name']} has no outages recorded.", link: page_link(page)) if outages.empty?

          rows = outages.map do |outage|
            [ "#{outage.dig('component', 'name')} #{outage['status']} (id #{outage['id']})", "from #{outage['from']}", ("to #{outage['to']}" if outage["to"]),
              ("incident #{outage.dig('incident', 'name')}" if outage["incident"]) ].compact.join(", ")
          end
          Telemetry.result("Outages on #{page['name']}:\n#{rows.join("\n")}", link: page_link(page))
        end

        def list_teammates(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          members = teammates(environment_row, page)
          return Telemetry.result("Nobody manages #{page['name']} in Instatus.", link: page_link(page)) if members.empty?

          Telemetry.result("Teammates on #{page['name']}:\n#{members.map { |member| "#{member.dig('user', 'name')} #{member.dig('user', 'email')} (member #{member['id']})".squish }.join("\n")}",
                           link: page_link(page))
        end

        def create_metric(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          body = { "subdomain" => page["subdomain"], "name" => required(arguments, "name"), "suffix" => arguments["suffix"].to_s.strip.presence }.compact
          made = api(environment_row).create_metric(page["id"], body)
          Telemetry.result("Instatus added metric #{body['name']} (id #{made['id']}) to #{page['name']}.", link: page_link(page))
        end

        def update_metric(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          metric = metric_of(environment_row, page, arguments["metric"])
          body = { "name" => arguments["name"].to_s.strip.presence, "suffix" => arguments["suffix"].to_s.strip.presence }.compact
          fail! "Name what to change: name or suffix." if body.empty?

          api(environment_row).update_metric(page["id"], metric["id"], body)
          Telemetry.result("Instatus changed #{body.keys.to_sentence(last_word_connector: ' and ')} of metric #{metric_name(metric)} on #{page['name']}.", link: page_link(page))
        end

        def delete_metric(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          metric = metric_of(environment_row, page, arguments["metric"])
          api(environment_row).delete_metric(page["id"], metric["id"])
          Telemetry.result("Instatus removed metric #{metric_name(metric)} from #{page['name']}.", link: page_link(page))
        end

        def add_metric_data(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          metric = metric_of(environment_row, page, arguments["metric"])
          points = Array(arguments["points"]).map do |point|
            given = point.to_h.stringify_keys
            fail! "Each point has a value that is a number." unless given["value"].is_a?(Numeric)

            { "timestamp" => (time_of(given["at"], "at").to_r * 1000).to_i, "value" => given["value"] }
          end
          fail! "Give at least one point." if points.empty?
          fail! "Send at most #{POINTS_LIMIT} points at a time." if points.size > POINTS_LIMIT

          api(environment_row).add_metric_data(page["id"], metric["id"], points)
          Telemetry.result("Instatus took #{points.size} #{points.one? ? 'reading' : 'readings'} for #{metric_name(metric)} on #{page['name']}.", link: page_link(page))
        end

        def delete_metric_data(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          metric = metric_of(environment_row, page, arguments["metric"])
          api(environment_row).delete_metric_data(page["id"], metric["id"])
          Telemetry.result("Instatus deleted every reading of #{metric_name(metric)} on #{page['name']}.", link: page_link(page))
        end

        def create_notice(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          body = { "name" => required(arguments, "name"), "message" => arguments["message"].to_s.strip.presence, "notify" => notify(arguments),
                   "isCollapsed" => arguments["collapsed"] == true }.compact
          made = api(environment_row).create_notice(page["id"], body)
          Telemetry.result("Instatus shows notice #{body['name']} (id #{made['id']}) on #{page['name']}.#{body['notify'] ? ' Subscribers were told.' : ' Subscribers were not told.'}",
                           link: page_link(page))
        end

        def update_notice(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          id = id_of(arguments, "notice")
          body = { "name" => arguments["name"].to_s.strip.presence, "message" => arguments["message"].to_s.strip.presence }.compact
          body["isCollapsed"] = arguments["collapsed"] if [ true, false ].include?(arguments["collapsed"])
          fail! "Name what to change: name, message or collapsed." if body.empty?

          api(environment_row).update_notice(page["id"], id, body)
          Telemetry.result("Instatus changed notice #{id} on #{page['name']}.", link: page_link(page))
        end

        def delete_notice(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          id = id_of(arguments, "notice")
          api(environment_row).delete_notice(page["id"], id)
          Telemetry.result("Instatus took notice #{id} off #{page['name']}.", link: page_link(page))
        end

        def create_outage(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          component = component_of(environment_row, page, arguments["component"])
          body = outage_body(arguments).merge("componentId" => component["id"])
          fail! "Give status and from." unless body["status"] && body["from"]

          made = api(environment_row).create_outage(page["id"], body)
          Telemetry.result("Instatus recorded a #{body['status']} outage of #{component['name']} (id #{made['id']}) from #{body['from']}#{" to #{body['to']}" if body['to']}.",
                           link: page_link(page))
        end

        def update_outage(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          id = id_of(arguments, "outage")
          body = outage_body(arguments)
          fail! "Name what to change: status, from or to." if body.empty?

          api(environment_row).update_outage(page["id"], id, body)
          Telemetry.result("Instatus changed #{body.keys.to_sentence(last_word_connector: ' and ')} of outage #{id} on #{page['name']}.", link: page_link(page))
        end

        def delete_outage(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          id = id_of(arguments, "outage")
          api(environment_row).delete_outage(page["id"], id)
          Telemetry.result("Instatus removed outage #{id} from #{page['name']}.", link: page_link(page))
        end

        def add_teammate(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          email = required(arguments, "email")
          made = api(environment_row).add_teammate(page["id"], email)
          Telemetry.result("Instatus invited #{email} to manage #{page['name']} (member #{made['id']}).", link: page_link(page))
        end

        def remove_teammate(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          wanted = required(arguments, "member")
          member = teammates(environment_row, page).find { |each| each["id"] == wanted || each.dig("user", "email").to_s.casecmp?(wanted) } ||
                   fail!("Nobody managing #{page['name']} is #{wanted}. list_teammates shows them.")
          api(environment_row).remove_teammate(page["id"], member["id"])
          Telemetry.result("Instatus took away #{member.dig('user', 'email') || member['id']}'s access to manage #{page['name']}.", link: page_link(page))
        end

        private

        def all_metrics(environment_row, page) = (@metrics ||= {})[page["id"]] ||= api(environment_row).metrics(page["id"]).items

        def teammates(environment_row, page) = (@teammates ||= {})[page["id"]] ||= api(environment_row).teammates(page["id"]).items

        # Instatus gives a metric's name as text, or in a list as its translations with the default under default.
        def metric_name(metric) = metric["name"].is_a?(Hash) ? metric["name"]["default"].to_s : metric["name"].to_s

        def metric_of(environment_row, page, wanted)
          wanted = wanted.to_s.strip
          fail! "Name the metric by its id or name." if wanted.empty?

          found = all_metrics(environment_row, page)
          found.find { |metric| metric["id"] == wanted } || found.find { |metric| metric_name(metric).casecmp?(wanted) } ||
            fail!("#{page['name']} has no metric #{wanted}. list_metrics shows them.")
        end

        def outage_body(arguments)
          { "status" => choice(arguments["status"], OUTAGE_STATUSES, "status"),
            "from" => (time_of(arguments["from"], "from").utc.iso8601(3) if arguments["from"].present?),
            "to" => (time_of(arguments["to"], "to").utc.iso8601(3) if arguments["to"].present?) }.compact
        end
      end
    end
  end
end
