module Integrations
  module Packs
    class Instatus < NativePack
      # How Instatus is run beside its pages: the workspaces the key's user is in, audience groups that decide who sees what
      # on a private page, third party monitoring tools that open incidents, and its on-call side of routing rules,
      # escalation policies and on-call schedules. A monitoring tool's own keys and the address it sends to are set up in
      # Instatus and the tool, so an integration's answer is read for its id, tool and label alone.
      module Operations
        ACTION_TYPES = %w[NOTIFY_TEAM NOTIFY_TEAM_MEMBER NOTIFY_CURRENT_ON_CALL_USER NOTIFY_NEXT_ON_CALL_USER NOTIFY_ALL_ON_CALL_MEMBERS].freeze
        ASSERTION_TYPES = %w[IMPACT TITLE DESCRIPTION AFFECTED_COMPONENTS].freeze
        COMPARISONS = %w[EQUALS NOT_EQUALS IS_EMPTY NOT_EMPTY GREATER_THAN GREATER_THAN_OR_EQUALS LESS_THAN LESS_THAN_OR_EQUALS CONTAINS NOT_CONTAINS
                         HAS_KEY NOT_HAS_KEY HAS_VALUE NOT_HAS_VALUE IS_NULL NOT_NULL STARTS_WITH ENDS_WITH].freeze
        ESCALATION_CONDITIONS = %w[NOT_ACKNOWLEDGED].freeze
        ROTATION_TYPES = %w[DAILY WEEKLY CUSTOM].freeze
        RESTRICTION_TYPES = %w[NONE TIMEOFDAY TIMEINTERVALS].freeze
        DAYS = %w[MONDAY TUESDAY WEDNESDAY THURSDAY FRIDAY SATURDAY SUNDAY].freeze
        WORKSPACE_SWITCHES = %w[send_new_workspace_members_status_page_updates send_new_workspace_members_automation_integration_notifications
                                send_new_workspace_members_invalid_custom_domain_notifications send_new_workspace_members_phone_call_notifications
                                send_new_workspace_members_weekly_reports_notifications].freeze

        ACTIONS = {
          "type" => "array",
          "items" => { "type" => "object", "properties" => {
            "type" => { "type" => "string", "enum" => ACTION_TYPES },
            "target" => { "type" => "string", "description" => "For NOTIFY_TEAM a team id, for NOTIFY_TEAM_MEMBER a teammate's email or id, else none" }
          }, "required" => [ "type" ] },
          "description" => "Who is told"
        }.freeze
        ASSERTIONS = {
          "type" => "array",
          "items" => { "type" => "object", "properties" => {
            "type" => { "type" => "string", "enum" => ASSERTION_TYPES }, "comparison" => { "type" => "string", "enum" => COMPARISONS },
            "value" => { "type" => "string", "description" => "What it is compared with (optional for IS_EMPTY and the like)" }
          }, "required" => %w[type comparison] },
          "description" => "What an event must match, all of them"
        }.freeze
        RULES = {
          "type" => "array",
          "items" => { "type" => "object", "properties" => {
            "delay_minutes" => { "type" => "integer", "description" => "Minutes to wait before this step" },
            "condition" => { "type" => "string", "enum" => ESCALATION_CONDITIONS, "description" => "When it applies (optional, NOT_ACKNOWLEDGED)" },
            "actions" => ACTIONS
          }, "required" => %w[delay_minutes actions] },
          "description" => "Its steps, in order"
        }.freeze
        SHIFTS = {
          "type" => "array",
          "items" => { "type" => "object", "properties" => {
            "name" => { "type" => "string" },
            "members" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Teammates in rotation order, by email or member id" },
            "rotation" => { "type" => "string", "enum" => ROTATION_TYPES },
            "custom_rotation_value" => { "type" => "integer", "description" => "For CUSTOM, how many units each turn lasts (optional)" },
            "custom_rotation_unit" => { "type" => "string", "description" => "For CUSTOM, the unit, as Instatus names it (optional)" },
            "starts" => { "type" => "string", "description" => "When it starts, as an ISO 8601 time" },
            "ends" => { "type" => "string", "description" => "When it ends, as an ISO 8601 time (optional)" },
            "restriction" => { "type" => "string", "enum" => RESTRICTION_TYPES, "description" => "When in the day or week it applies (optional, NONE)" },
            "day_starts" => { "type" => "string", "description" => "For TIMEOFDAY, the time it starts, such as 09:00 (optional)" },
            "day_ends" => { "type" => "string", "description" => "For TIMEOFDAY, the time it ends, such as 17:00 (optional)" },
            "intervals" => {
              "type" => "array",
              "items" => { "type" => "object", "properties" => {
                "start_day" => { "type" => "string", "enum" => DAYS }, "start_time" => { "type" => "string", "description" => "Such as 21:00" },
                "end_day" => { "type" => "string", "enum" => DAYS }, "end_time" => { "type" => "string", "description" => "Such as 03:00" }
              }, "required" => %w[start_day start_time end_day end_time] },
              "description" => "For TIMEINTERVALS, the spans of the week it covers (optional)"
            }
          }, "required" => %w[name members rotation starts] },
          "description" => "Its shifts"
        }.freeze
        SCHEDULE = { "type" => "string", "description" => "The on-call schedule's id" }.freeze

        def self.included(pack)
          pack.tool :list_workspaces,
                    summary: "Lists your Instatus workspaces and the pages in each.",
                    description: "The Instatus workspaces this key's user is in, each with its id, slug and the pages in it",
                    params_schema: { "type" => "object", "properties" => {} },
                    read_only: true

          pack.tool :list_audience_groups,
                    summary: "Lists a private page's audience groups with their teammates and components.",
                    description: "A private page's audience groups, each with the teammates in it and the components they see",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
                    read_only: true

          pack.tool :list_routing_rules,
                    summary: "Lists the routing rules that decide who hears about an incident.",
                    description: "Who Instatus tells about an incident, by rule: what an incident must match and who each rule notifies",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
                    read_only: true

          pack.tool :list_escalation_policies,
                    summary: "Lists Instatus escalation policies with their steps and timing.",
                    description: "Instatus's escalation policies, each with its steps, who each step notifies after how long, and how it repeats",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE } },
                    read_only: true

          pack.tool :who_is_on_call,
                    summary: "Shows who is on call now and next on an Instatus on-call schedule.",
                    description: "Who is on call now and next on an Instatus on-call schedule, and everyone in its rotation",
                    params_schema: { "type" => "object", "properties" => { "schedule" => SCHEDULE }, "required" => [ "schedule" ] },
                    read_only: true

          pack.tool :create_workspace,
                    summary: "Creates an Instatus workspace.",
                    description: "Make an Instatus workspace",
                    params_schema: { "type" => "object", "properties" => {
                      "name" => { "type" => "string", "description" => "Its name" }, "slug" => { "type" => "string", "description" => "Its slug" },
                      "long_running_incident_hours" => { "type" => "array", "items" => { "type" => "number" },
                                                         "description" => "Hours after which members are told an incident is still open, such as [0.5, 1, 2] (optional)" }
                    }.merge(WORKSPACE_SWITCHES.to_h { |switch| [ switch, { "type" => "boolean", "description" => "#{switch.tr('_', ' ').upcase_first} (optional)" } ] }),
                                     "required" => %w[name slug] },
                    read_only: false

          pack.tool :delete_workspace,
                    summary: "Deletes an Instatus workspace for good.",
                    description: "Delete an Instatus workspace for good",
                    params_schema: { "type" => "object", "properties" => { "workspace" => { "type" => "string", "description" => "The workspace, by id or slug" } }, "required" => [ "workspace" ] },
                    read_only: false

          pack.tool :create_audience_group,
                    summary: "Creates an audience group on a private page.",
                    description: "Make an audience group on a private page, the teammates who see the components named",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "name" => { "type" => "string", "description" => "Its name" },
                      "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "The components it sees, by id or name" },
                      "teammates" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Its teammates, by email or member id" }
                    }, "required" => [ "name" ] },
                    read_only: false

          pack.tool :update_audience_group,
                    summary: "Renames an audience group or sets its teammates and components.",
                    description: "Rename an audience group or set its teammates and components",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "group" => { "type" => "string", "description" => "The audience group, by id or name" },
                      "name" => { "type" => "string", "description" => "A new name (optional)" },
                      "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Every component it sees after (optional)" },
                      "teammates" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Every teammate in it after (optional)" }
                    }, "required" => [ "group" ] },
                    read_only: false

          pack.tool :delete_audience_group,
                    summary: "Removes an audience group from a private page.",
                    description: "Remove an audience group from a private page",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "group" => { "type" => "string", "description" => "The audience group, by id or name" } }, "required" => [ "group" ] },
                    read_only: false

          pack.tool :create_monitoring_integration,
                    summary: "Connects a monitoring service such as Pingdom to open and resolve incidents.",
                    description: "Connect a third party monitoring tool, such as Pingdom or New Relic, to open and resolve incidents for the " \
                                 "components named. The tool's own keys and the address it sends to are set in Instatus and the tool",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "tool" => { "type" => "string", "description" => "The monitoring tool as Instatus names it, such as PINGDOM or NEWRELIC" },
                      "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "The components it opens incidents for, by id or name" }
                    }, "required" => %w[tool components] },
                    read_only: false

          pack.tool :update_monitoring_integration,
                    summary: "Changes a monitoring integration's name, components or incident names.",
                    description: "Rename a monitoring integration, change its components, or name the incidents it opens and resolves",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "integration" => { "type" => "string", "description" => "The integration's id" },
                      "label" => { "type" => "string", "description" => "Its label (optional)" },
                      "components" => { "type" => "array", "items" => { "type" => "string" }, "description" => "Every component it covers after (optional)" },
                      "incident_name" => { "type" => "string", "description" => "The name of an incident it opens (optional)" },
                      "resolved_name" => { "type" => "string", "description" => "The name it gives an incident it resolves (optional)" }
                    }, "required" => [ "integration" ] },
                    read_only: false

          pack.tool :delete_monitoring_integration,
                    summary: "Disconnects a monitoring integration.",
                    description: "Disconnect a monitoring integration",
                    params_schema: { "type" => "object", "properties" => { "integration" => { "type" => "string", "description" => "The integration's id" } }, "required" => [ "integration" ] },
                    read_only: false

          pack.tool :create_routing_rule,
                    summary: "Adds a routing rule that decides who hears about matching incidents.",
                    description: "Add a routing rule: who Instatus tells about an incident that matches",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "assertions" => ASSERTIONS, "actions" => ACTIONS, "order" => { "type" => "integer", "description" => "Its place among the rules (optional)" }
                    }, "required" => %w[assertions actions] },
                    read_only: false

          pack.tool :update_routing_rule,
                    summary: "Changes what a routing rule matches, who it tells, or its order.",
                    description: "Change what a routing rule matches, who it tells, or its place among the rules",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE, "rule" => { "type" => "string", "description" => "The routing rule's id, as list_routing_rules shows it" },
                      "assertions" => ASSERTIONS.merge("description" => "What an event must match after (optional)"),
                      "actions" => ACTIONS.merge("description" => "Who is told after (optional)"), "order" => { "type" => "integer", "description" => "Its place (optional)" }
                    }, "required" => [ "rule" ] },
                    read_only: false

          pack.tool :delete_routing_rule,
                    summary: "Removes a routing rule.",
                    description: "Remove a routing rule",
                    params_schema: { "type" => "object", "properties" => { "rule" => { "type" => "string", "description" => "The routing rule's id" } }, "required" => [ "rule" ] },
                    read_only: false

          pack.tool :create_escalation_policy,
                    summary: "Creates an escalation policy for incidents nobody has acknowledged.",
                    description: "Make an escalation policy: who is notified, step by step, while an incident is not acknowledged",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE }.merge(escalation_fields), "required" => %w[name rules] },
                    read_only: false

          pack.tool :update_escalation_policy,
                    summary: "Changes an escalation policy's name, steps or repeats.",
                    description: "Change an escalation policy's name, steps or how it repeats. Its steps are replaced by the ones given",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "policy" => { "type" => "string", "description" => "The policy's id or name" } }.merge(escalation_fields),
                                     "required" => [ "policy" ] },
                    read_only: false

          pack.tool :delete_escalation_policy,
                    summary: "Removes an escalation policy.",
                    description: "Remove an escalation policy",
                    params_schema: { "type" => "object", "properties" => { "page" => PAGE, "policy" => { "type" => "string", "description" => "The policy's id or name" } }, "required" => [ "policy" ] },
                    read_only: false

          pack.tool :create_on_call_schedule,
                    summary: "Creates an on-call schedule of rotating shifts.",
                    description: "Make an on-call schedule of shifts, each a rotation of teammates",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE.merge("description" => "The page whose teammates are named by email (optional when the key reaches one page)"),
                      "name" => { "type" => "string", "description" => "Its name" }, "description" => { "type" => "string", "description" => "What it covers (optional)" },
                      "shifts" => SHIFTS
                    }, "required" => %w[name shifts] },
                    read_only: false

          pack.tool :update_on_call_schedule,
                    summary: "Changes an on-call schedule's name or description, or replaces its shifts.",
                    description: "Change an on-call schedule's name or description, or replace its shifts",
                    params_schema: { "type" => "object", "properties" => {
                      "page" => PAGE.merge("description" => "The page whose teammates are named by email (optional when the key reaches one page)"),
                      "schedule" => SCHEDULE, "name" => { "type" => "string", "description" => "A new name (optional)" },
                      "description" => { "type" => "string", "description" => "A new description (optional)" },
                      "shifts" => SHIFTS.merge("description" => "Every shift after (optional)")
                    }, "required" => [ "schedule" ] },
                    read_only: false

          pack.tool :delete_on_call_schedule,
                    summary: "Removes an on-call schedule.",
                    description: "Remove an on-call schedule",
                    params_schema: { "type" => "object", "properties" => { "schedule" => SCHEDULE }, "required" => [ "schedule" ] },
                    read_only: false
        end

        def self.escalation_fields
          {
            "name" => { "type" => "string", "description" => "Its name" }, "description" => { "type" => "string", "description" => "What it is for (optional)" },
            "rules" => RULES,
            "repeat" => { "type" => "boolean", "description" => "Go through its steps again when nobody acknowledged (optional)" },
            "repeat_count" => { "type" => "integer", "description" => "How many times it repeats (optional)" },
            "repeat_delay" => { "type" => "integer", "description" => "Minutes between repeats (optional)" },
            "auto_resolve_after_repeat" => { "type" => "boolean", "description" => "Resolve the incident once it stops repeating (optional)" },
            "revert_acknowledgement" => { "type" => "boolean", "description" => "Take an acknowledgement back when it repeats (optional)" }
          }
        end

        def list_workspaces(environment_row:, arguments:)
          workspaces = api(environment_row).workspaces.items
          return Telemetry.result("This key's user is in no Instatus workspaces.", link: nil) if workspaces.empty?

          rows = workspaces.map { |workspace| "#{workspace['name']} (id #{workspace['id']}, slug #{workspace['slug']}), #{Array(workspace['sites']).size} pages" }
          Telemetry.result("Instatus workspaces:\n#{rows.join("\n")}", link: nil)
        end

        def list_audience_groups(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          groups = audience_groups(environment_row, page)
          return Telemetry.result("#{page['name']} has no audience groups.", link: page_link(page)) if groups.empty?

          rows = groups.map do |group|
            people = Array(group["teammates"]).filter_map { |each| each.dig("teammate", "user", "email") }
            components = Array(group["components"]).filter_map { |each| each.dig("component", "name") }
            "#{group['name']} (id #{group['id']}): #{people.any? ? people.join(', ') : 'no teammates'}, seeing #{components.any? ? components.join(', ') : 'no components'}"
          end
          Telemetry.result("Audience groups on #{page['name']}:\n#{rows.join("\n")}", link: page_link(page))
        end

        def list_routing_rules(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          rules = api(environment_row).routing_rules(page["id"])
          return Telemetry.result("#{page['name']} has no routing rules.", link: page_link(page)) if rules.empty?

          rows = rules.sort_by { |rule| rule["order"].to_i }.map do |rule|
            matches = Array(rule["assertions"]).map { |each| [ each["type"], each["comparison"], each["value"] ].compact.join(" ") }
            told = Array(rule["actions"]).map { |each| [ each["type"], each["targetId"] ].compact.join(" ") }
            "Rule #{rule['id']} (order #{rule['order']}): when #{matches.join(' and ').presence || 'anything'}, #{told.join(', ').presence || 'nobody is told'}"
          end
          Telemetry.result("Routing rules on #{page['name']}:\n#{rows.join("\n")}", link: page_link(page))
        end

        def list_escalation_policies(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          policies = api(environment_row).escalation_policies(page["id"])
          return Telemetry.result("#{page['name']} has no escalation policies.", link: page_link(page)) if policies.empty?

          Telemetry.result(policies.map { |policy| escalation_lines(policy) }.join("\n\n"), link: page_link(page))
        end

        def who_is_on_call(environment_row:, arguments:)
          id = id_of(arguments, "schedule")
          members = api(environment_row).on_call_members(id).to_h
          names = ->(key) { Array(members[key]).map { |each| each["name"].presence || each["email"] }.presence&.join(", ") || "nobody" }
          Telemetry.result("On call now on schedule #{id}: #{names.('currentMembers')}. Next: #{names.('nextMembers')}. In the rotation: #{names.('allMembers')}.", link: nil)
        end

        def create_workspace(environment_row:, arguments:)
          body = { "name" => required(arguments, "name"), "slug" => required(arguments, "slug") }
          WORKSPACE_SWITCHES.each { |switch| body[switch.camelize(:lower)] = arguments[switch] if [ true, false ].include?(arguments[switch]) }
          hours = Array(arguments["long_running_incident_hours"]).select { |each| each.is_a?(Numeric) }
          body["longRunningIncidentNotificationSettings"] = hours if hours.any?
          made = api(environment_row).create_workspace(body)
          Telemetry.result("Instatus made workspace #{body['name']} (id #{made['id']}, slug #{made['slug'] || body['slug']}).", link: nil)
        end

        def delete_workspace(environment_row:, arguments:)
          wanted = required(arguments, "workspace")
          workspace = api(environment_row).workspaces.items.find { |each| each["id"] == wanted || each["slug"].to_s.casecmp?(wanted) } ||
                      fail!("This key's user is in no workspace #{wanted}. list_workspaces shows them.")
          api(environment_row).delete_workspace(workspace["id"])
          Telemetry.result("Instatus deleted workspace #{workspace['name']} (id #{workspace['id']}).", link: nil)
        end

        def create_audience_group(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          body = { "name" => required(arguments, "name"), "components" => component_ids(environment_row, page, arguments["components"]),
                   "teammates" => teammate_ids(environment_row, page, arguments["teammates"]) }
          made = api(environment_row).create_audience_group(page["id"], body)
          Telemetry.result("Instatus made audience group #{body['name']} (id #{made['id']}) on #{page['name']}.", link: page_link(page))
        end

        def update_audience_group(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          group = audience_group_of(environment_row, page, arguments["group"])
          body = { "name" => arguments["name"].to_s.strip.presence }.compact
          body["components"] = component_ids(environment_row, page, arguments["components"]) unless arguments["components"].nil?
          body["teammates"] = teammate_ids(environment_row, page, arguments["teammates"]) unless arguments["teammates"].nil?
          fail! "Name what to change: name, components or teammates." if body.empty?

          api(environment_row).update_audience_group(page["id"], group["id"], body)
          Telemetry.result("Instatus changed #{body.keys.to_sentence(last_word_connector: ' and ')} of audience group #{group['name']} on #{page['name']}.", link: page_link(page))
        end

        def delete_audience_group(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          group = audience_group_of(environment_row, page, arguments["group"])
          api(environment_row).delete_audience_group(page["id"], group["id"])
          Telemetry.result("Instatus removed audience group #{group['name']} from #{page['name']}.", link: page_link(page))
        end

        def create_monitoring_integration(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          tool = required(arguments, "tool").upcase
          components = component_ids(environment_row, page, arguments["components"])
          fail! "Name the components it opens incidents for." if components.empty?

          made = api(environment_row).create_integration("pageId" => page["id"], "integrationType" => tool, "components" => components).to_h["integration"].to_h
          Telemetry.result("Instatus connected #{made['monitoringTool'] || tool} (id #{made['id']}) for #{components.size} components on #{page['name']}. " \
                           "Point #{tool.titleize} at Instatus from Instatus's integration page, since the address it sends to works as a password.", link: page_link(page))
        end

        def update_monitoring_integration(environment_row:, arguments:)
          id = id_of(arguments, "integration")
          body = { "label" => arguments["label"].to_s.strip.presence }.compact
          unless arguments["components"].nil?
            page = page_of(environment_row, arguments)
            body["components"] = component_ids(environment_row, page, arguments["components"])
          end
          body["createTemplate"] = { "name" => arguments["incident_name"].to_s.strip } if arguments["incident_name"].present?
          body["resolveTemplate"] = { "name" => arguments["resolved_name"].to_s.strip } if arguments["resolved_name"].present?
          fail! "Name what to change: label, components, incident_name or resolved_name." if body.empty?

          api(environment_row).update_integration(id, body)
          Telemetry.result("Instatus changed #{body.keys.map { |key| key.underscore.tr('_', ' ') }.to_sentence(last_word_connector: ' and ')} of integration #{id}.", link: nil)
        end

        def delete_monitoring_integration(environment_row:, arguments:)
          id = id_of(arguments, "integration")
          api(environment_row).delete_integration(id)
          Telemetry.result("Instatus disconnected integration #{id}.", link: nil)
        end

        def create_routing_rule(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          rule = { "siteId" => page["id"], "assertions" => assertions_of(arguments["assertions"]), "actions" => actions_of(environment_row, page, arguments["actions"]),
                   "order" => (arguments["order"] if arguments["order"].is_a?(Integer)) }.compact
          fail! "Give at least one assertion and one action." if rule["assertions"].empty? || rule["actions"].empty?

          made = api(environment_row).create_routing_rule(rule).to_h["routingRule"].to_h
          Telemetry.result("Instatus added routing rule #{made['id']} on #{page['name']}, telling #{rule['actions'].size} when an incident matches #{rule['assertions'].size} conditions.",
                           link: page_link(page))
        end

        def update_routing_rule(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          id = id_of(arguments, "rule")
          rule = { "id" => id, "siteId" => page["id"], "order" => (arguments["order"] if arguments["order"].is_a?(Integer)) }.compact
          rule["assertions"] = assertions_of(arguments["assertions"]) unless arguments["assertions"].nil?
          rule["actions"] = actions_of(environment_row, page, arguments["actions"]) unless arguments["actions"].nil?
          fail! "Name what to change: assertions, actions or order." if rule.keys == %w[id siteId]

          api(environment_row).update_routing_rule(id, rule)
          Telemetry.result("Instatus changed routing rule #{id} on #{page['name']}.", link: page_link(page))
        end

        def delete_routing_rule(environment_row:, arguments:)
          id = id_of(arguments, "rule")
          api(environment_row).delete_routing_rule(id)
          Telemetry.result("Instatus removed routing rule #{id}.", link: nil)
        end

        def create_escalation_policy(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          body = escalation_body(environment_row, page, arguments).merge("pageId" => page["id"], "name" => required(arguments, "name"))
          fail! "Give at least one step in rules." if Array(body["rules"]).empty?

          made = api(environment_row).create_escalation_policy(body).to_h["escalationPolicy"].to_h
          Telemetry.result("Instatus made escalation policy #{body['name']}#{" (id #{made['id']})" if made['id']} with #{body['rules'].size} steps on #{page['name']}.", link: page_link(page))
        end

        def update_escalation_policy(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          policy = escalation_policy_of(environment_row, page, arguments["policy"])
          body = escalation_body(environment_row, page, arguments)
          body["name"] = arguments["name"].to_s.strip if arguments["name"].present?
          fail! "Name what to change on the policy." if body.empty?

          api(environment_row).update_escalation_policy(policy["id"], body.merge("pageId" => page["id"]))
          Telemetry.result("Instatus changed #{body.keys.map { |key| key.underscore.tr('_', ' ') }.to_sentence(last_word_connector: ' and ')} of escalation policy #{policy['name']}.",
                           link: page_link(page))
        end

        def delete_escalation_policy(environment_row:, arguments:)
          page = page_of(environment_row, arguments)
          policy = escalation_policy_of(environment_row, page, arguments["policy"])
          api(environment_row).delete_escalation_policy(policy["id"])
          Telemetry.result("Instatus removed escalation policy #{policy['name']}.", link: page_link(page))
        end

        def create_on_call_schedule(environment_row:, arguments:)
          shifts = shifts_of(environment_row, arguments)
          fail! "Give at least one shift." if shifts.empty?

          body = { "name" => required(arguments, "name"), "description" => arguments["description"].to_s.strip.presence, "onCallShifts" => shifts }.compact
          made = api(environment_row).create_on_call_schedule(body)
          Telemetry.result("Instatus made on-call schedule #{body['name']} (id #{made['id']}) with #{shifts.size} shifts. who_is_on_call reads who is on it.", link: nil)
        end

        def update_on_call_schedule(environment_row:, arguments:)
          id = id_of(arguments, "schedule")
          body = { "name" => arguments["name"].to_s.strip.presence, "description" => arguments["description"].to_s.strip.presence }.compact
          body["onCallShifts"] = shifts_of(environment_row, arguments) unless arguments["shifts"].nil?
          fail! "Name what to change: name, description or shifts." if body.empty?

          api(environment_row).update_on_call_schedule(id, body.merge("id" => id))
          Telemetry.result("Instatus changed #{body.keys.map { |key| key.underscore.tr('_', ' ') }.to_sentence(last_word_connector: ' and ')} of on-call schedule #{id}.", link: nil)
        end

        def delete_on_call_schedule(environment_row:, arguments:)
          id = id_of(arguments, "schedule")
          api(environment_row).delete_on_call_schedule(id)
          Telemetry.result("Instatus removed on-call schedule #{id}.", link: nil)
        end

        private

        def audience_groups(environment_row, page) = (@audience_groups ||= {})[page["id"]] ||= api(environment_row).audience_groups(page["id"]).items

        def audience_group_of(environment_row, page, wanted)
          wanted = wanted.to_s.strip
          fail! "Name the audience group by its id or name." if wanted.empty?

          found = audience_groups(environment_row, page)
          found.find { |group| group["id"] == wanted } || found.find { |group| group["name"].to_s.casecmp?(wanted) } ||
            fail!("#{page['name']} has no audience group #{wanted}. list_audience_groups shows them.")
        end

        def escalation_policy_of(environment_row, page, wanted)
          wanted = wanted.to_s.strip
          fail! "Name the escalation policy by its id or name." if wanted.empty?

          found = (@escalation_policies ||= {})[page["id"]] ||= api(environment_row).escalation_policies(page["id"])
          found.find { |policy| policy["id"] == wanted } || found.find { |policy| policy["name"].to_s.casecmp?(wanted) } ||
            fail!("#{page['name']} has no escalation policy #{wanted}. list_escalation_policies shows them.")
        end

        # Teammates by their member id, named by it or by their email on the page's team.
        def teammate_ids(environment_row, page, given)
          Array(given).map do |each|
            wanted = each.to_s.strip
            member = teammates(environment_row, page).find { |member| member["id"] == wanted || member.dig("user", "email").to_s.casecmp?(wanted) } ||
                     fail!("Nobody managing #{page['name']} is #{wanted}. list_teammates shows them.")
            member["id"]
          end.uniq
        end

        def assertions_of(given)
          Array(given).map do |each|
            assertion = each.to_h.stringify_keys
            type = choice(assertion["type"], ASSERTION_TYPES, "An assertion's type") || fail!("Each assertion has a type.")
            comparison = choice(assertion["comparison"], COMPARISONS, "An assertion's comparison") || fail!("Each assertion has a comparison.")
            { "type" => type, "comparison" => comparison, "value" => assertion["value"]&.to_s }.compact
          end
        end

        # A team member is named by email in a routing rule's action, as Instatus documents, and by member id elsewhere.
        def actions_of(environment_row, page, given, member_by: :email)
          Array(given).map do |each|
            action = each.to_h.stringify_keys
            type = choice(action["type"], ACTION_TYPES, "An action's type") || fail!("Each action has a type.")
            target = action["target"].to_s.strip.presence
            fail! "#{type} needs a target." if %w[NOTIFY_TEAM NOTIFY_TEAM_MEMBER].include?(type) && target.nil?
            if type == "NOTIFY_TEAM_MEMBER"
              member = teammates(environment_row, page).find { |one| one["id"] == target || one.dig("user", "email").to_s.casecmp?(target) } ||
                       fail!("Nobody managing #{page['name']} is #{target}. list_teammates shows them.")
              target = member_by == :email ? member.dig("user", "email") : member["id"]
            end
            { "type" => type, "targetId" => target }.compact
          end
        end

        def escalation_body(environment_row, page, arguments)
          body = { "description" => arguments["description"].to_s.strip.presence }.compact
          unless arguments["rules"].nil?
            body["rules"] = Array(arguments["rules"]).map do |each|
              rule = each.to_h.stringify_keys
              fail! "Each step has delay_minutes, a whole number." unless rule["delay_minutes"].is_a?(Integer)

              { "delayInMins" => rule["delay_minutes"], "condition" => choice(rule["condition"], ESCALATION_CONDITIONS, "condition") || ESCALATION_CONDITIONS.first,
                "actions" => actions_of(environment_row, page, rule["actions"], member_by: :id) }
            end
          end
          body["repeat"] = arguments["repeat"] if [ true, false ].include?(arguments["repeat"])
          body["repeatCount"] = arguments["repeat_count"] if arguments["repeat_count"].is_a?(Integer)
          body["repeatDelay"] = arguments["repeat_delay"] if arguments["repeat_delay"].is_a?(Integer)
          body["autoResolveIncidentsAfterRepeat"] = arguments["auto_resolve_after_repeat"] if [ true, false ].include?(arguments["auto_resolve_after_repeat"])
          body["revertAcknowledgement"] = arguments["revert_acknowledgement"] if [ true, false ].include?(arguments["revert_acknowledgement"])
          body
        end

        # Instatus keeps a time of day as that time on 1 January 1970, in UTC.
        def time_of_day(value, name)
          match = value.to_s.strip.match(/\A(\d{1,2}):(\d{2})\z/) || fail!("#{name} is a time of day such as 09:00.")
          hours, minutes = match.captures.map(&:to_i)
          fail! "#{name} is a time of day such as 09:00." unless hours < 24 && minutes < 60

          format("1970-01-01T%<hours>02d:%<minutes>02d:00.000Z", hours: hours, minutes: minutes)
        end

        def shifts_of(environment_row, arguments)
          page = nil
          Array(arguments["shifts"]).map do |each|
            shift = each.to_h.stringify_keys
            members = Array(shift["members"]).map do |member|
              wanted = member.to_s.strip
              next wanted if wanted.match?(INSTATUS_ID)

              page ||= page_of(environment_row, arguments)
              teammate_ids(environment_row, page, [ wanted ]).first
            end
            fail! "Each shift names its members." if members.empty?

            restriction = choice(shift["restriction"], RESTRICTION_TYPES, "restriction") || RESTRICTION_TYPES.first
            {
              "name" => shift["name"].to_s.strip.presence || fail!("Each shift has a name."),
              "members" => members.map { |id| { "teamMemberId" => id } },
              "rotationType" => choice(shift["rotation"], ROTATION_TYPES, "rotation") || fail!("Each shift has a rotation."),
              "customRotationTypeValue" => (shift["custom_rotation_value"] if shift["custom_rotation_value"].is_a?(Integer)),
              "customRotationTypeUnit" => shift["custom_rotation_unit"].to_s.strip.presence,
              "startDate" => time_of(shift["starts"], "starts").utc.iso8601(3),
              "endDate" => (time_of(shift["ends"], "ends").utc.iso8601(3) if shift["ends"].present?),
              "restrictionType" => restriction,
              "timeOfDayRestrictionStartTime" => (time_of_day(shift["day_starts"], "day_starts") if restriction == "TIMEOFDAY"),
              "timeOfDayRestrictionEndTime" => (time_of_day(shift["day_ends"], "day_ends") if restriction == "TIMEOFDAY"),
              "timeIntervals" => (intervals_of(shift["intervals"]) if restriction == "TIMEINTERVALS")
            }.compact
          end
        end

        def intervals_of(given)
          intervals = Array(given).map do |each|
            span = each.to_h.stringify_keys
            { "startDay" => choice(span["start_day"], DAYS, "start_day") || fail!("Each interval has a start_day."), "startDayTime" => time_of_day(span["start_time"], "start_time"),
              "endDay" => choice(span["end_day"], DAYS, "end_day") || fail!("Each interval has an end_day."), "endDayTime" => time_of_day(span["end_time"], "end_time") }
          end
          fail! "TIMEINTERVALS needs at least one interval." if intervals.empty?

          intervals
        end

        def escalation_lines(policy)
          steps = Array(policy["rules"]).sort_by { |rule| rule["order"].to_i }.map do |rule|
            told = Array(rule["actions"]).map { |each| [ each["type"], each["targetId"] ].compact.join(" ") }
            "- after #{rule['delayInMins']} minutes, #{rule['condition']}, #{told.join(', ')}"
          end
          repeat = policy["repeat"] ? "repeats #{policy['repeatCount']} times, #{policy['repeatDelay']} minutes apart" : "does not repeat"
          [ "#{policy['name']} (id #{policy['id']}), #{repeat}", *steps ].join("\n")
        end
      end
    end
  end
end
