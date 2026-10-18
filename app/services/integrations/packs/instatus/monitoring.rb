module Integrations
  module Packs
    class Instatus < NativePack
      # Instatus's own monitoring: monitors that check an address, the alerts they send, the groups they sit in, and cron
      # monitors that wait for a job's pings. A monitor's basic auth and any header or query parameter named like a
      # credential, a cron monitor's ping address (its slug, which works as a password) and an alert's webhook address
      # would pass through the call, the activity log and the answer, so they are never taken, and never shown. Those are
      # set in Instatus itself.
      module Monitoring
        MONITOR = { "type" => "string", "description" => "The monitor's id, as list_monitors shows it" }.freeze
        CRON = { "type" => "string", "description" => "The cron monitor's id, as list_cron_monitors shows it" }.freeze
        MONITOR_GROUP = { "type" => "string", "description" => "The monitor group's id, as list_monitors shows it on its monitors" }.freeze
        ALERT = { "type" => "string", "description" => "The monitor alert's id, as list_monitor_alerts shows it" }.freeze
        MONITOR_IDS = { "type" => "array", "items" => { "type" => "string" }, "description" => "Monitor ids, as list_monitors shows them" }.freeze
        LOCATION = { "type" => "string", "enum" => InstatusApi::MONITOR_LOCATIONS, "description" => "Where to check from (optional)" }.freeze
        LOG_LIMIT = 50
        LOG_MOST = 1_000
        CRON_LOG_MOST = 127
        # A header or query parameter with one of these in its name carries a credential.
        SECRET_NAME = /auth|token|key|secret|password|cookie|session|signature/i
        EMAIL = /\A[^@\s\/]+@[^@\s\/]+\.[^@\s\/]+\z/
        PHONE = /\A\+?[\d\s().-]{6,20}\z/
        ON_FAIL = {
          "type" => "object",
          "properties" => {
            "create_incident" => { "type" => "boolean" }, "create_outage_duration" => { "type" => "boolean" },
            "publish_incident" => { "type" => "boolean" }, "notify_subscribers" => { "type" => "boolean" }
          },
          "description" => "What Instatus does when it fails: open an incident, record an outage, publish the incident, tell subscribers (optional)"
        }.freeze
        ON_RECOVER = {
          "type" => "object",
          "properties" => {
            "resolve_incident" => { "type" => "boolean" }, "resolve_outage_duration" => { "type" => "boolean" },
            "publish_incident" => { "type" => "boolean" }, "notify_subscribers" => { "type" => "boolean" }
          },
          "description" => "What Instatus does when it recovers: resolve the incident, end the outage, publish, tell subscribers (optional)"
        }.freeze
        MONITOR_FIELDS = {
          "name" => { "type" => "string", "description" => "Its name" },
          "url" => { "type" => "string", "description" => "The address it checks" },
          "http_method" => { "type" => "string", "description" => "The method it sends, such as GET (optional, GET)" },
          "body" => { "type" => "string", "description" => "The body it sends (optional)" },
          "headers" => { "type" => "object", "additionalProperties" => { "type" => "string" },
                         "description" => "Headers it sends, none of them a credential, which are set in Instatus (optional)" },
          "query_params" => { "type" => "object", "additionalProperties" => { "type" => "string" },
                              "description" => "Query parameters it adds, none of them a credential (optional)" },
          "assertions" => {
            "type" => "array",
            "items" => { "type" => "object", "properties" => { "type" => { "type" => "string", "description" => "Such as STATUSCODE" },
                                                               "comparison" => { "type" => "string", "description" => "Such as EQUALS" },
                                                               "selector" => { "type" => "string" }, "target" => { "type" => "string" } } },
            "description" => "What its answer must show to pass, such as a STATUSCODE that EQUALS 200 (optional)"
          },
          "alerts" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Monitor alert ids it sends (optional)" },
          "locations" => LOCATION,
          "checks_interval" => { "type" => "integer", "description" => "Seconds between checks, such as 300 (optional)" },
          "create_component" => { "type" => "boolean", "description" => "Add a component that follows it (optional)" },
          "create_metric" => { "type" => "boolean", "description" => "Add a metric of its response time (optional)" },
          "on_fail" => ON_FAIL, "on_recover" => ON_RECOVER
        }.freeze

        def self.included(pack)
          pack.tool :list_monitors,
                    summary: "Lists the uptime monitors checking a page's addresses and their status.",
                    description: "The monitors checking a page's addresses, each with its id, the address, how often, from where, its group and " \
                                 "status: UP, DOWN, DEGRADED or UNKNOWN",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "search" => { "type" => "string", "description" => "Words in its name (optional)" },
                      "status" => { "type" => "string", "enum" => InstatusApi::MONITOR_STATUSES, "description" => "Only these (optional)" }
                    } },
                    read_only: true

          pack.tool :get_monitor_logs,
                    summary: "Shows a monitor's latest checks with status codes and response times.",
                    description: "A monitor's latest checks, newest first, with where each ran from, its status, HTTP code and response time",
                    params_schema: { "type" => "object", "properties" => {
                      "monitor" => MONITOR,
                      "status" => { "type" => "string", "enum" => InstatusApi::MONITOR_STATUSES, "description" => "Only checks with this status (optional)" },
                      "successful" => { "type" => "boolean", "description" => "Only checks that passed, or failed (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many, up to #{LOG_MOST} (optional, #{LOG_LIMIT})" }
                    }, "required" => [ "monitor" ] },
                    read_only: true

          pack.tool :list_monitor_alerts,
                    summary: "Lists where a page's monitors send their alerts.",
                    description: "Where a page's monitors send alerts, each with its id, kind, the monitors it covers and when it fires. A webhook's address is not shown",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
                    read_only: true

          pack.tool :list_cron_monitors,
                    summary: "Lists the cron monitors watching a page's scheduled jobs and their status.",
                    description: "The cron monitors waiting for a page's scheduled jobs to ping, each with its id, how often the job runs, " \
                                 "its grace, state and status. The ping address is not shown, since it works as a password",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "search" => { "type" => "string", "description" => "Words in its name (optional)" },
                      "status" => { "type" => "string", "enum" => InstatusApi::MONITOR_STATUSES, "description" => "Only these (optional)" }
                    } },
                    read_only: true

          pack.tool :get_cron_monitor,
                    summary: "Shows how a cron monitor's job has run, with its availability and latest pings.",
                    description: "How a cron monitor's job has run: its availability over a day, a week and a month, its last success and " \
                                 "failure, and its latest pings",
                    params_schema: { "type" => "object", "properties" => {
                      "cron" => CRON, "important" => { "type" => "boolean", "description" => "Only failures, misses and late pings (optional)" },
                      "limit" => { "type" => "integer", "description" => "At most this many pings, up to #{CRON_LOG_MOST} (optional, #{LOG_LIMIT})" }
                    }, "required" => [ "cron" ] },
                    read_only: true

          pack.tool :create_monitor,
                    summary: "Creates an uptime monitor that checks an address on a schedule.",
                    description: "Start a monitor that checks an address on a schedule, which can open and resolve incidents on the page itself",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE }.merge(MONITOR_FIELDS), "required" => %w[name url] },
                    read_only: false

          pack.tool :update_monitor,
                    summary: "Changes what a monitor checks, how often, from where, or how it reacts.",
                    description: "Change what a monitor checks, how often, from where, or what it does when it fails or recovers",
                    params_schema: { "type" => "object", "properties" => { "monitor" => MONITOR }.merge(MONITOR_FIELDS.transform_values { |field| field.merge("description" => "#{field['description'].to_s.sub(/ \(optional.*\)\z/, '')} (optional)") }),
                                     "required" => [ "monitor" ] },
                    read_only: false

          pack.tool :delete_monitor,
                    summary: "Stops and removes an uptime monitor.",
                    description: "Stop and remove a monitor",
                    params_schema: { "type" => "object", "properties" => { "monitor" => MONITOR }, "required" => [ "monitor" ] },
                    read_only: false

          pack.tool :run_monitor_check,
                    summary: "Runs a monitor's check right away.",
                    description: "Run a monitor's check now. A check that fails can open an incident, as the monitor is set to",
                    params_schema: { "type" => "object", "properties" => { "monitor" => MONITOR, "location" => LOCATION }, "required" => [ "monitor" ] },
                    read_only: false

          pack.tool :create_monitor_alert,
                    summary: "Sends a page's monitor alerts by email, SMS, phone call, WhatsApp or incident.",
                    description: "Send a page's monitors' alerts by email, SMS, phone call or WhatsApp, or as an incident. Slack, Discord, " \
                                 "Teams, Google Chat and webhook alerts take an address that works as a password, so they are added in Instatus",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE,
                      "type" => { "type" => "string", "enum" => InstatusApi::ALERT_TYPES - InstatusApi::WEBHOOK_ALERTS, "description" => "How it is sent" },
                      "recipient" => { "type" => "string", "description" => "The email or phone number, not for INCIDENT (optional)" },
                      "monitors" => MONITOR_IDS
                    }.merge(alert_switches), "required" => %w[type monitors] },
                    read_only: false

          pack.tool :update_monitor_alert,
                    summary: "Changes which monitors an alert covers, when it fires, or where it goes.",
                    description: "Change which monitors an alert covers, when it fires, or its email or phone number",
                    params_schema: { "type" => "object", "properties" => {
                      "alert" => ALERT, "recipient" => { "type" => "string", "description" => "A new email or phone number (optional)" },
                      "monitors" => MONITOR_IDS.merge("description" => "Every monitor it covers after (optional)")
                    }.merge(alert_switches), "required" => [ "alert" ] },
                    read_only: false

          pack.tool :delete_monitor_alert,
                    summary: "Stops a monitor alert.",
                    description: "Stop a monitor alert",
                    params_schema: { "type" => "object", "properties" => { "alert" => ALERT }, "required" => [ "alert" ] },
                    read_only: false

          pack.tool :create_monitor_group,
                    summary: "Creates a group to keep monitors together.",
                    description: "Make a group to keep monitors together, which add_monitors_to_group fills",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "name" => { "type" => "string", "description" => "Its name" } }, "required" => [ "name" ] },
                    read_only: false

          pack.tool :update_monitor_group,
                    summary: "Renames a monitor group.",
                    description: "Rename a monitor group",
                    params_schema: { "type" => "object", "properties" => { "group" => MONITOR_GROUP, "name" => { "type" => "string", "description" => "Its new name" } }, "required" => %w[group name] },
                    read_only: false

          pack.tool :add_monitors_to_group,
                    summary: "Adds monitors to a monitor group.",
                    description: "Put monitors in a monitor group",
                    params_schema: { "type" => "object", "properties" => { "group" => MONITOR_GROUP, "monitors" => MONITOR_IDS }, "required" => %w[group monitors] },
                    read_only: false

          pack.tool :delete_monitor_group,
                    summary: "Removes a monitor group.",
                    description: "Remove a monitor group",
                    params_schema: { "type" => "object", "properties" => { "group" => MONITOR_GROUP }, "required" => [ "group" ] },
                    read_only: false

          pack.tool :run_monitor_group_check,
                    summary: "Runs the checks of every monitor in a group right away.",
                    description: "Run the checks of every monitor in a group now. A check that fails can open an incident, as its monitor is set to",
                    params_schema: { "type" => "object", "properties" => { "group" => MONITOR_GROUP, "location" => LOCATION }, "required" => [ "group" ] },
                    read_only: false

          pack.tool :create_cron_monitor,
                    summary: "Creates a cron monitor that marks a scheduled job down when it misses a ping.",
                    description: "Start a cron monitor that waits for a scheduled job to ping, and marks it down when a ping does not come in " \
                                 "time. Its ping address is in Instatus, since it works as a password",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE }.merge(cron_fields), "required" => %w[name period] },
                    read_only: false

          pack.tool :update_cron_monitor,
                    summary: "Changes a cron monitor's schedule, grace or reactions, or pauses or mutes it.",
                    description: "Change a cron monitor's schedule or grace, pause or mute it, or what it does when the job fails or recovers",
                    params_schema: { "type" => "object", "properties" => { "cron" => CRON }.merge(cron_fields).merge(
                      "state" => { "type" => "string", "enum" => InstatusApi::CRON_STATES, "description" => "ACTIVE, PAUSED or MUTED (optional)" }
                    ), "required" => [ "cron" ] },
                    read_only: false

          pack.tool :delete_cron_monitor,
                    summary: "Removes a cron monitor.",
                    description: "Remove a cron monitor. Its job's pings then go nowhere",
                    params_schema: { "type" => "object", "properties" => { "cron" => CRON }, "required" => [ "cron" ] },
                    read_only: false
        end

        def self.alert_switches
          {
            "when_fails" => { "type" => "boolean", "description" => "Send when a monitor fails (optional)" },
            "when_recovers" => { "type" => "boolean", "description" => "Send when it recovers (optional)" },
            "when_degrades" => { "type" => "boolean", "description" => "Send when it degrades (optional)" },
            "when_ssl_expires" => { "type" => "boolean", "description" => "Send before its certificate expires (optional)" },
            "ssl_expires_in_days" => { "type" => "integer", "description" => "How many days before (optional)" }
          }
        end

        def self.cron_fields
          {
            "name" => { "type" => "string", "description" => "Its name" },
            "period" => { "type" => "integer", "description" => "Seconds between the job's runs, such as 86400 for daily" },
            "grace" => { "type" => "integer", "description" => "Seconds a late ping is still on time (optional)" },
            "alerts" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Monitor alert ids it sends (optional)" },
            "create_component" => { "type" => "boolean", "description" => "Add a component that follows it (optional)" },
            "on_fail" => ON_FAIL, "on_recover" => ON_RECOVER
          }
        end

        def list_monitors(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          read = api(environment_row).monitors(page["id"], search: arguments["search"].to_s.strip,
                                                           status: choice(arguments["status"], InstatusApi::MONITOR_STATUSES, "status"))
          return Telemetry.result("No monitors on #{page['name']} match.", link: page_link(page)) if read.items.empty?

          rows = read.items.map do |monitor|
            [ "#{monitor['name']} (id #{monitor['id']})", monitor["status"], ("#{monitor['httpMethod']} " if monitor["httpMethod"]).to_s + monitor["url"].to_s,
              ("every #{monitor['checksInterval']} seconds" if monitor["checksInterval"]), ("from #{Array(monitor['locations']).join(', ')}" if monitor["locations"].present?),
              ("group #{monitor['groupId']}" if monitor["groupId"]) ].compact_blank.join(", ")
          end
          more = read.incomplete? ? "\nThere are more. Narrow it with search or status." : ""
          Telemetry.result("Monitors on #{page['name']}:\n#{rows.join("\n")}#{more}", link: page_link(page))
        end

        def get_monitor_logs(environment_row:, arguments:)
          id = id_of(arguments, "monitor")
          successful = [ true, false ].include?(arguments["successful"]) ? arguments["successful"] : nil
          answer = api(environment_row).monitor_logs(id, limit: Capabilities::Answers.limit(arguments, LOG_MOST, default: LOG_LIMIT),
                                                         status: choice(arguments["status"], InstatusApi::MONITOR_STATUSES, "status"), successful: successful)
          logs = Array(answer.to_h["monitorLogs"])
          return Telemetry.result("Monitor #{id} has no checks that match.", link: nil) if logs.empty?

          rows = logs.map do |log|
            [ log["createdAt"], log["location"], log["status"], ("HTTP #{log['httpStatusCode']}" if log["httpStatusCode"]),
              ("#{log['responseTime']} ms" if log["responseTime"]), (log["isSuccessful"] == false ? "failed" : nil) ].compact.join(", ")
          end
          Telemetry.result("Latest checks of monitor #{id}, #{answer['total'] || logs.size} in all:\n#{rows.join("\n")}", link: nil)
        end

        def list_monitor_alerts(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          alerts = api(environment_row).monitor_alerts(page["id"]).items
          return Telemetry.result("#{page['name']} sends no monitor alerts.", link: page_link(page)) if alerts.empty?

          rows = alerts.map do |alert|
            hidden = InstatusApi::WEBHOOK_ALERTS.include?(alert["type"])
            when_words = %w[whenFails whenRecovers whenDegrades whenSslExpires].select { |key| alert[key] }.map { |key| key.delete_prefix("when").underscore.tr("_", " ") }
            [ "#{alert['type']} (id #{alert['id']})", (alert["recipient"].present? && !hidden ? "to #{alert['recipient']}" : nil),
              ("on #{when_words.join(', ')}" if when_words.any?), "#{Array(alert['monitors']).size} monitors" ].compact.join(", ")
          end
          Telemetry.result("Monitor alerts on #{page['name']}:\n#{rows.join("\n")}", link: page_link(page))
        end

        def list_cron_monitors(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          read = api(environment_row).cron_monitors(page["id"], search: arguments["search"].to_s.strip,
                                                                status: choice(arguments["status"], InstatusApi::MONITOR_STATUSES, "status"))
          return Telemetry.result("No cron monitors on #{page['name']} match.", link: page_link(page)) if read.items.empty?

          rows = read.items.map do |cron|
            [ "#{cron['name']} (id #{cron['id']})", cron["status"], cron["state"], "every #{cron['period']} seconds",
              ("grace #{cron['grace']} seconds" if cron["grace"]) ].compact.join(", ")
          end
          Telemetry.result("Cron monitors on #{page['name']}:\n#{rows.join("\n")}", link: page_link(page))
        end

        def get_cron_monitor(environment_row:, arguments:)
          id = id_of(arguments, "cron")
          summary = api(environment_row).cron_summary(id).to_h["summary"].to_h
          logs = Array(api(environment_row).cron_logs(id, limit: Capabilities::Answers.limit(arguments, CRON_LOG_MOST, default: LOG_LIMIT),
                                                          important: arguments["important"] == true).to_h["logs"])
          head = [ ("available #{summary['oneDayAvailability']}% in a day, #{summary['sevenDayAvailability']}% in a week, #{summary['thirtyDayAvailability']}% in a month" if summary.any?),
                   ("last success #{summary['lastSuccess']}" if summary["lastSuccess"]), ("last failure #{summary['lastFailure']}" if summary["lastFailure"]),
                   ("down since #{summary['downSince']}" if summary["downSince"]), ("up since #{summary['upSince']}" if summary["upSince"]) ].compact.join(", ")
          pings = logs.map { |log| "#{log['createdAt']} #{log['status']}#{" started #{log['startedAt']}" if log['startedAt']}" }
          Telemetry.result([ "Cron monitor #{id}: #{head.presence || 'no summary yet'}.", ("Latest pings:\n#{pings.join("\n")}" if pings.any?) ].compact.join("\n"), link: nil)
        end

        def create_monitor(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          body = monitor_body(arguments).merge("pageId" => page["id"], "name" => required(arguments, "name"), "url" => required(arguments, "url"))
          body["httpMethod"] ||= "GET"
          body["type"] = InstatusApi::MONITOR_TYPES.first
          made = api(environment_row).create_monitor(body).to_h["monitor"].to_h
          Telemetry.result("Instatus started monitor #{made['name'] || body['name']}#{" (id #{made['id']})" if made['id']} checking #{body['url']} on #{page['name']}.", link: page_link(page))
        end

        def update_monitor(environment_row:, arguments:)
          id = id_of(arguments, "monitor")
          body = monitor_body(arguments)
          fail! "Name what to change on the monitor." if body.empty?

          api(environment_row).update_monitor(id, body)
          Telemetry.result("Instatus changed #{body.keys.map { |key| key.underscore.tr('_', ' ') }.to_sentence(last_word_connector: ' and ')} of monitor #{id}.", link: nil)
        end

        def delete_monitor(environment_row:, arguments:)
          id = id_of(arguments, "monitor")
          api(environment_row).delete_monitor(id)
          Telemetry.result("Instatus removed monitor #{id}.", link: nil)
        end

        def run_monitor_check(environment_row:, arguments:)
          id = id_of(arguments, "monitor")
          answer = api(environment_row).run_monitor(id, location: choice(arguments["location"], InstatusApi::MONITOR_LOCATIONS, "location"))
          Telemetry.result(Sentence.join("Instatus ran monitor #{id}'s check", answer.to_h["message"] || answer.to_h["status"]), link: nil)
        end

        def create_monitor_alert(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          type = arguments["type"].to_s
          refuse_webhook_alert!(type)
          fail! "type is one of #{(InstatusApi::ALERT_TYPES - InstatusApi::WEBHOOK_ALERTS).join(', ')}." unless InstatusApi::ALERT_TYPES.include?(type)

          monitors = ids_of(arguments, "monitors")
          fail! "Name the monitors it covers." if monitors.empty?

          body = alert_body(arguments).merge("pageId" => page["id"], "type" => type, "monitors" => monitors)
          made = api(environment_row).create_monitor_alert(body).to_h["monitor"].to_h
          Telemetry.result("Instatus will send #{type} alerts#{" to #{body['recipient']}" if body['recipient']} for #{monitors.size} monitors#{" (id #{made['id']})" if made['id']}.",
                           link: page_link(page))
        end

        def update_monitor_alert(environment_row:, arguments:)
          id = id_of(arguments, "alert")
          body = alert_body(arguments)
          body["monitors"] = ids_of(arguments, "monitors") unless arguments["monitors"].nil?
          fail! "Name what to change on the alert." if body.empty?

          api(environment_row).update_monitor_alert(id, body)
          Telemetry.result("Instatus changed #{body.keys.map { |key| key.underscore.tr('_', ' ') }.to_sentence(last_word_connector: ' and ')} of monitor alert #{id}.", link: nil)
        end

        def delete_monitor_alert(environment_row:, arguments:)
          id = id_of(arguments, "alert")
          api(environment_row).delete_monitor_alert(id)
          Telemetry.result("Instatus stopped monitor alert #{id}.", link: nil)
        end

        def create_monitor_group(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          made = api(environment_row).create_monitor_group("pageId" => page["id"], "name" => required(arguments, "name")).to_h["monitor"].to_h
          Telemetry.result("Instatus made monitor group #{arguments['name'].to_s.strip}#{" (id #{made['id']})" if made['id']} on #{page['name']}.", link: page_link(page))
        end

        def update_monitor_group(environment_row:, arguments:)
          id = id_of(arguments, "group")
          api(environment_row).update_monitor_group(id, "name" => required(arguments, "name"))
          Telemetry.result("Instatus renamed monitor group #{id} to #{arguments['name'].to_s.strip}.", link: nil)
        end

        def add_monitors_to_group(environment_row:, arguments:)
          id = id_of(arguments, "group")
          monitors = ids_of(arguments, "monitors")
          fail! "Name the monitors to put in it." if monitors.empty?

          api(environment_row).add_monitors_to_group(id, monitors)
          Telemetry.result("Instatus put #{monitors.size} monitors in group #{id}.", link: nil)
        end

        def delete_monitor_group(environment_row:, arguments:)
          id = id_of(arguments, "group")
          api(environment_row).delete_monitor_group(id)
          Telemetry.result("Instatus removed monitor group #{id}.", link: nil)
        end

        def run_monitor_group_check(environment_row:, arguments:)
          id = id_of(arguments, "group")
          answer = api(environment_row).run_monitor_group(id, location: choice(arguments["location"], InstatusApi::MONITOR_LOCATIONS, "location"))
          Telemetry.result(Sentence.join("Instatus ran the checks of monitor group #{id}", answer.to_h["result"]), link: nil)
        end

        def create_cron_monitor(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          body = cron_body(arguments).merge("pageId" => page["id"], "name" => required(arguments, "name"))
          fail! "Give period, the seconds between the job's runs." unless body["period"].to_i.positive?

          made = api(environment_row).create_cron_monitor(body).to_h["cronMonitor"].to_h
          Telemetry.result("Instatus started cron monitor #{made['name'] || body['name']}#{" (id #{made['id']})" if made['id']} on #{page['name']}, expecting a ping every " \
                           "#{body['period']} seconds. Its ping address is in Instatus, on the monitor's page.", link: page_link(page))
        end

        def update_cron_monitor(environment_row:, arguments:)
          id = id_of(arguments, "cron")
          body = cron_body(arguments)
          body["name"] = arguments["name"].to_s.strip if arguments["name"].present?
          body["state"] = choice(arguments["state"], InstatusApi::CRON_STATES, "state") if arguments["state"].present?
          fail! "Name what to change on the cron monitor." if body.empty?

          api(environment_row).update_cron_monitor(id, body)
          Telemetry.result("Instatus changed #{body.keys.map { |key| key.underscore.tr('_', ' ') }.to_sentence(last_word_connector: ' and ')} of cron monitor #{id}.", link: nil)
        end

        def delete_cron_monitor(environment_row:, arguments:)
          id = id_of(arguments, "cron")
          api(environment_row).delete_cron_monitor(id)
          Telemetry.result("Instatus removed cron monitor #{id}.", link: nil)
        end

        private

        def ids_of(arguments, key) = Array(arguments[key]).map { |each| each.to_s.strip }.compact_blank.uniq

        def monitor_body(arguments)
          body = { "name" => arguments["name"].to_s.strip.presence, "url" => arguments["url"].to_s.strip.presence,
                   "httpMethod" => arguments["http_method"].to_s.strip.upcase.presence, "body" => arguments["body"].presence,
                   "locations" => choice(arguments["locations"], InstatusApi::MONITOR_LOCATIONS, "locations"),
                   "checksInterval" => (arguments["checks_interval"] if arguments["checks_interval"].is_a?(Integer)) }.compact
          body["headers"] = no_credentials(arguments["headers"], "headers") unless arguments["headers"].nil?
          body["queryParams"] = no_credentials(arguments["query_params"], "query_params") unless arguments["query_params"].nil?
          body["assertions"] = Array(arguments["assertions"]).map { |each| each.to_h.stringify_keys.slice("type", "comparison", "selector", "target") } unless arguments["assertions"].nil?
          body["alerts"] = ids_of(arguments, "alerts") unless arguments["alerts"].nil?
          %w[create_component create_metric].each { |key| body[key.camelize(:lower)] = arguments[key] if [ true, false ].include?(arguments[key]) }
          body.merge(outcomes(arguments))
        end

        def cron_body(arguments)
          body = { "period" => (arguments["period"] if arguments["period"].is_a?(Integer)), "grace" => (arguments["grace"] if arguments["grace"].is_a?(Integer)) }.compact
          body["alerts"] = ids_of(arguments, "alerts") unless arguments["alerts"].nil?
          body["createComponent"] = arguments["create_component"] if [ true, false ].include?(arguments["create_component"])
          body.merge(outcomes(arguments))
        end

        # on_fail and on_recover as Instatus takes them, each switch by its own name.
        def outcomes(arguments)
          %w[on_fail on_recover].each_with_object({}) do |key, body|
            given = arguments[key].to_h.stringify_keys.select { |_switch, value| [ true, false ].include?(value) }
            body[key.camelize(:lower)] = given.transform_keys { |switch| switch.camelize(:lower) } if given.any?
          end
        end

        # A recipient is an email or a phone number. Anything else, such as a webhook address, works as a password.
        def alert_body(arguments)
          recipient = arguments["recipient"].to_s.strip.presence
          if recipient && !recipient.match?(EMAIL) && !recipient.match?(PHONE)
            fail_policy!("An alert's recipient here is an email or a phone number. A webhook address works as a password, so set it in Instatus, under Monitoring, Alerts.")
          end

          body = { "recipient" => recipient }.compact
          %w[when_fails when_recovers when_degrades when_ssl_expires].each { |key| body[key.camelize(:lower)] = arguments[key] if [ true, false ].include?(arguments[key]) }
          body["sslExpiresInDays"] = arguments["ssl_expires_in_days"] if arguments["ssl_expires_in_days"].is_a?(Integer)
          body
        end

        def refuse_webhook_alert!(type)
          return unless InstatusApi::WEBHOOK_ALERTS.include?(type)

          fail_policy!("A #{type} alert sends to an address that works as a password, so add it in Instatus, under Monitoring, Alerts.")
        end

        # Names and values a monitor sends, refused when a name says it carries a credential, which belongs in Instatus.
        def no_credentials(given, name)
          pairs = given.to_h.to_h { |key, value| [ key.to_s, value.to_s ] }
          secret = pairs.keys.find { |key| key.match?(SECRET_NAME) }
          fail_policy!("#{name} names #{secret}, which carries a credential. Set it on the monitor in Instatus, so it never passes through Firefight.") if secret
          pairs
        end
      end
    end
  end
end
