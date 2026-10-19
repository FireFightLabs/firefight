module Integrations
  module Packs
    # Opsgenie, read with the key of an API integration the workspace creates in Opsgenie: who is on call now and next,
    # the escalations that page people, and the alerts and incidents open now. Raising, acknowledging, escalating,
    # snoozing, assigning and closing an alert, adding a responder or a note to it, resolving and closing an incident,
    # overriding a schedule and starting a maintenance window change Opsgenie, so a member needs a grant for them, they
    # ask before they run in a chat and they are never used while investigating. Opsgenie's API gives no page address for
    # anything it returns and documents none, so results carry no link. The executor hides anything that looks like a
    # credential in what comes back.
    class Opsgenie < NativePack
      # The one credential this pack keeps. It has no plain settings to ask for.
      API_KEY = "api_key".freeze

      ALERT_LIMIT = 20
      INCIDENT_LIMIT = 20
      TIMELINE_LIMIT = 20
      SCHEDULES_SHOWN = 25
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
      # Opsgenie's own format for a schedule's dates, such as 2026-10-11T08:00:00Z.
      SCHEDULE_TIME = "%Y-%m-%dT%H:%M:%SZ".freeze
      DEFAULT_IDENTIFIER_TYPE = OpsgenieApi::IDENTIFIER_TYPES.first

      ALERT = {
        "alert" => { "type" => "string", "description" => "The alert, by its id, its tiny id (the short number Opsgenie shows) or its alias" },
        "identifier_type" => { "type" => "string", "enum" => OpsgenieApi::IDENTIFIER_TYPES,
                               "description" => "Which of these alert names: id, tiny or alias (optional, id). An alias only finds an open alert" }
      }.freeze
      NOTE = { "type" => "string", "description" => "A note Opsgenie adds to the alert, saying why (optional)" }.freeze
      INCIDENT = {
        "incident" => { "type" => "string", "description" => "The incident, by its id or its tiny id (the short number Opsgenie shows)" },
        "identifier_type" => { "type" => "string", "enum" => %w[id tiny], "description" => "Which of these incident names: id or tiny (optional, id)" },
        "note" => { "type" => "string", "description" => "A note Opsgenie adds to the incident, saying why (optional)" }
      }.freeze
      RESPONDER = {
        "type" => "object",
        "properties" => {
          "type" => { "type" => "string", "enum" => OpsgenieApi::RESPONDER_TYPES, "description" => "What the responder is" },
          "name" => { "type" => "string", "description" => "Its name, or for a user their email" }
        },
        "required" => %w[type name]
      }.freeze
      SCHEDULE = { "type" => "string", "description" => "The schedule, by its name or id, as who_is_on_call shows it" }.freeze

      tool :who_is_on_call,
           summary: "Shows who is on call now, for one schedule or every schedule.",
           description: "Who is on call now in Opsgenie, for one schedule or for every schedule with the team that owns it. Use it to " \
                        "find who to page or who is already being paged",
           params_schema: {
             "type" => "object",
             "properties" => {
               "schedule" => { "type" => "string", "description" => "One schedule, by its name or id (optional, every schedule)" }
             }
           },
           read_only: true

      tool :who_is_on_call_next,
           summary: "Shows who comes on call next on a schedule.",
           description: "Who comes on call next in Opsgenie on one schedule, with overrides counted. Use it to say who takes over " \
                        "and to find who to override",
           params_schema: { "type" => "object", "properties" => { "schedule" => SCHEDULE }, "required" => [ "schedule" ] },
           read_only: true

      tool :list_escalations,
           summary: "Lists the escalation policies with who each one notifies and when.",
           description: "The escalation policies in Opsgenie: who each one notifies, in what order, after how long and on which " \
                        "condition. Use it to see who an alert reaches next, and for the name escalate_alert takes",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :search_alerts,
           summary: "Searches alerts with their status, priority and owner.",
           description: "Alerts in Opsgenie, newest first, with their status, priority, how many times each fired and who owns or " \
                        "acknowledged it. query uses Opsgenie's alert search, such as status: open AND acknowledged: false",
           params_schema: {
             "type" => "object",
             "properties" => {
               "query" => { "type" => "string", "description" => "An Opsgenie alert search query, such as status: open or message: checkout (optional, every alert)" },
               "limit" => { "type" => "integer", "description" => "At most this many, up to #{OpsgenieApi::PAGE_LIMIT} (optional, #{ALERT_LIMIT})" }
             }
           },
           read_only: true

      tool :get_alert,
           summary: "Shows one alert in full with its notes and history.",
           description: "One Opsgenie alert in full: its message, description, details, tags, responders and how it was handled, " \
                        "with its latest notes and its log of what happened to it",
           params_schema: { "type" => "object", "properties" => ALERT, "required" => [ "alert" ] },
           read_only: true

      tool :search_incidents,
           summary: "Searches incidents with their status, priority and affected services.",
           description: "Incidents in Opsgenie, newest first, with their status, priority and the services they affect. query uses " \
                        "Opsgenie's incident search, such as status: open",
           params_schema: {
             "type" => "object",
             "properties" => {
               "query" => { "type" => "string", "description" => "An Opsgenie incident search query, such as status: open (optional, every incident)" },
               "limit" => { "type" => "integer", "description" => "At most this many, up to #{OpsgenieApi::PAGE_LIMIT} (optional, #{INCIDENT_LIMIT})" }
             }
           },
           read_only: true

      tool :list_maintenance_targets,
           summary: "Lists the integrations and alert policies a maintenance window can quiet.",
           description: "The integrations and alert policies in Opsgenie, by name and id, which a maintenance window quiets. Use it " \
                        "for the ids create_maintenance takes",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :create_alert,
           summary: "Raises an alert that pages its responders.",
           description: "Raise an Opsgenie alert, which pages its responders through their escalations and schedules. Use it to " \
                        "wake someone, with what they need to know in the description",
           params_schema: {
             "type" => "object",
             "properties" => {
               "message" => { "type" => "string", "description" => "What is wrong, at most #{OpsgenieApi::MESSAGE_LIMIT} characters" },
               "description" => { "type" => "string", "description" => "What the person paged needs before they look: since when, the evidence and its links" },
               "responders" => { "type" => "array", "items" => RESPONDER, "description" => "Who to page: teams, escalations, schedules or users" },
               "priority" => { "type" => "string", "enum" => OpsgenieApi::PRIORITIES, "description" => "P1 is the most urgent (optional, P3)" },
               "alias" => { "type" => "string", "description" => "A key that keeps a second alert for the same problem from opening while this one is open (optional)" },
               "entity" => { "type" => "string", "description" => "What the alert is about, such as a service (optional)" }
             },
             "required" => %w[message responders]
           },
           read_only: false

      tool :acknowledge_alert,
           summary: "Acknowledges an alert so it stops escalating.",
           description: "Acknowledge an Opsgenie alert, which stops it paging further along its escalation. Say who is handling it " \
                        "in the note",
           params_schema: { "type" => "object", "properties" => ALERT.merge("note" => NOTE), "required" => [ "alert" ] },
           read_only: false

      tool :escalate_alert,
           summary: "Escalates an alert to an escalation policy, paging the people it names.",
           description: "Escalate an Opsgenie alert to an escalation policy, which pages the people it names. Find the policy with " \
                        "list_escalations first",
           params_schema: {
             "type" => "object",
             "properties" => ALERT.merge(
               "escalation" => { "type" => "string", "description" => "The escalation policy, by its name or id, as list_escalations shows it" },
               "note" => NOTE
             ),
             "required" => [ "alert", "escalation" ]
           },
           read_only: false

      tool :add_alert_note,
           summary: "Adds a note to an alert that everyone on it sees.",
           description: "Add a note to an Opsgenie alert, which everyone on it sees, such as what is known or which incident it belongs to",
           params_schema: {
             "type" => "object",
             "properties" => ALERT.merge("note" => { "type" => "string", "description" => "The note to add" }),
             "required" => [ "alert", "note" ]
           },
           read_only: false

      tool :close_alert,
           summary: "Closes an alert so it stops paging anyone.",
           description: "Close an Opsgenie alert once the problem is over, which stops it paging anyone",
           params_schema: { "type" => "object", "properties" => ALERT.merge("note" => NOTE), "required" => [ "alert" ] },
           read_only: false

      tool :snooze_alert,
           summary: "Snoozes an alert until a set time.",
           description: "Snooze an Opsgenie alert until a time, which stops it paging until then",
           params_schema: {
             "type" => "object",
             "properties" => ALERT.merge(
               "until" => { "type" => "string", "description" => "When it pages again, as an ISO 8601 time such as 2026-10-11T09:30:00Z" },
               "note" => NOTE
             ),
             "required" => %w[alert until]
           },
           read_only: false

      tool :assign_alert,
           summary: "Makes one person the owner of an alert.",
           description: "Make one person the owner of an Opsgenie alert",
           params_schema: {
             "type" => "object",
             "properties" => ALERT.merge("owner" => { "type" => "string", "description" => "The person's Opsgenie username, their email" }, "note" => NOTE),
             "required" => %w[alert owner]
           },
           read_only: false

      tool :add_responder,
           summary: "Brings a team or person into an alert, paging them.",
           description: "Bring a team or a person into an Opsgenie alert, which pages them without taking it off whoever has it",
           params_schema: {
             "type" => "object",
             "properties" => ALERT.merge(
               "responder_type" => { "type" => "string", "enum" => %w[team user], "description" => "A team or a user" },
               "responder" => { "type" => "string", "description" => "The team's name, or the user's email" },
               "note" => NOTE
             ),
             "required" => %w[alert responder_type responder]
           },
           read_only: false

      tool :resolve_incident,
           summary: "Resolves an Opsgenie incident.",
           description: "Resolve an Opsgenie incident once the problem is fixed",
           params_schema: { "type" => "object", "properties" => INCIDENT, "required" => [ "incident" ] },
           read_only: false

      tool :close_incident,
           summary: "Closes an Opsgenie incident for good.",
           description: "Close an Opsgenie incident, which ends it for good",
           params_schema: { "type" => "object", "properties" => INCIDENT, "required" => [ "incident" ] },
           read_only: false

      tool :create_schedule_override,
           summary: "Puts someone on call on a schedule for a while in place of the rotation.",
           description: "Put someone on call on an Opsgenie schedule for a while, in place of whoever the rotation names, such as " \
                        "when the person on call is out",
           params_schema: {
             "type" => "object",
             "properties" => {
               "schedule" => SCHEDULE,
               "user" => { "type" => "string", "description" => "Who goes on call, by their Opsgenie username, their email" },
               "start" => { "type" => "string", "description" => "When it starts, as an ISO 8601 time" },
               "end" => { "type" => "string", "description" => "When it ends, as an ISO 8601 time" }
             },
             "required" => %w[schedule user start end]
           },
           read_only: false

      tool :create_maintenance,
           summary: "Starts a maintenance window that quiets alerts during planned work.",
           description: "Start a maintenance window in Opsgenie, which quiets an integration's alerts or a policy for a while, such " \
                        "as during planned work. Find the ids with list_maintenance_targets",
           params_schema: {
             "type" => "object",
             "properties" => {
               "description" => { "type" => "string", "description" => "Why, such as the planned work (optional)" },
               "duration" => { "type" => "string", "enum" => OpsgenieApi::MAINTENANCE_TIMES,
                               "description" => "How long, or schedule to give start and end" },
               "start" => { "type" => "string", "description" => "For schedule: when it starts, as an ISO 8601 time" },
               "end" => { "type" => "string", "description" => "For schedule: when it ends, as an ISO 8601 time" },
               "targets" => {
                 "type" => "array",
                 "items" => {
                   "type" => "object",
                   "properties" => {
                     "type" => { "type" => "string", "enum" => OpsgenieApi::MAINTENANCE_ENTITIES, "description" => "An integration or an alert policy" },
                     "id" => { "type" => "string", "description" => "Its id, as list_maintenance_targets shows it" }
                   },
                   "required" => %w[type id]
                 },
                 "description" => "What to quiet: an integration's alerts stop, a policy stops acting"
               }
             },
             "required" => %w[duration targets]
           },
           read_only: false

      def self.credential_fields
        [
          CredentialField.new(key: API_KEY, label: "API key", secret: true, placeholder: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                              hint: "The key of an API integration, under Settings, Integrations, API in Opsgenie, not restricted to " \
                                    "access configurations. For Halon to change alerts, turn on Create and Update in its access rights.")
        ]
      end

      # Reads the account on the chosen region's instance before anything is saved, so the form says when a key is wrong
      # or belongs to the other instance.
      def self.credential_refusal(values, region: nil, fields: {})
        key = values[API_KEY].to_s.strip
        return "Paste an API key." if key.empty?

        OpsgenieApi.new(key, region: region&.key).account
        nil
      rescue OpsgenieApi::Unauthenticated
        "Opsgenie did not accept this key on its #{region&.label || 'US'} instance. Check the region, and that the API integration is turned on."
      rescue OpsgenieApi::Error => error
        Sentence.join("Opsgenie refused this key", error)
      end

      def self.store_credentials!(environment_row, values)
        environment_row.store_credential!(API_KEY, values[API_KEY].to_s.strip)
      end

      def who_is_on_call(environment_row:, arguments:)
        wanted = arguments["schedule"].to_s.strip
        if wanted.present?
          on_call = api(environment_row).on_calls(wanted, by_name: !wanted.match?(UUID))
          return on_call_line(on_call.dig("_parent", "name") || wanted, on_call)
        end

        schedules = api(environment_row).schedules.select { |schedule| schedule["enabled"] != false }
        return "Opsgenie has no enabled schedules." if schedules.empty?

        lines = schedules.first(SCHEDULES_SHOWN).map do |schedule|
          team = schedule.dig("ownerTeam", "name")
          on_call_line("#{schedule['name']}#{" (team #{team})" if team}", api(environment_row).on_calls(schedule["id"], by_name: false))
        end
        more = schedules.size > SCHEDULES_SHOWN ? "\n#{schedules.size - SCHEDULES_SHOWN} more schedules. Ask for one by name." : ""
        "On call now in Opsgenie:\n#{lines.join("\n")}#{more}"
      end

      def who_is_on_call_next(environment_row:, arguments:)
        wanted = arguments["schedule"].to_s.strip
        fail! "Name the schedule, as who_is_on_call shows it." if wanted.empty?

        next_up = api(environment_row).next_on_calls(wanted, by_name: !wanted.match?(UUID))
        people = Array(next_up["exactNextOnCallParticipants"]).presence || Array(next_up["nextOnCallParticipants"])
        name = next_up.dig("_parent", "name") || wanted
        people.any? ? "Next on call on #{name}: #{people.join(', ')}" : "Opsgenie names nobody next on #{name} in the next two weeks."
      end

      def list_maintenance_targets(environment_row:, arguments:)
        client = api(environment_row)
        integrations = client.integrations.map do |each|
          "- #{each['name']} (integration, id #{each['id']}, #{each['type']}#{', off' if each['enabled'] == false})"
        end
        policies = client.alert_policies.map { |each| "- #{each['name']} (policy, id #{each['id']}#{', off' if each['enabled'] == false})" }
        [ ("Integrations:\n#{integrations.join("\n")}" if integrations.any?), ("Alert policies:\n#{policies.join("\n")}" if policies.any?) ]
          .compact.join("\n\n").presence || "Opsgenie has no integrations or alert policies this key can see."
      end

      def list_escalations(environment_row:, arguments:)
        escalations = api(environment_row).escalations
        return "Opsgenie has no escalation policies." if escalations.empty?

        escalations.map { |escalation| escalation_lines(escalation) }.join("\n\n")
      end

      def search_alerts(environment_row:, arguments:)
        query = arguments["query"].to_s.strip
        alerts = api(environment_row).alerts(query: query, limit: Capabilities::Answers.limit(arguments, OpsgenieApi::PAGE_LIMIT, default: ALERT_LIMIT))
        heading = query.present? ? "Opsgenie alerts matching #{query}" : "Latest Opsgenie alerts"
        return "No Opsgenie alerts match#{" #{query}" if query.present?}." if alerts.empty?

        "#{heading}, newest first:\n#{alerts.map { |alert| alert_line(alert) }.join("\n")}"
      end

      def get_alert(environment_row:, arguments:)
        identifier, type = alert_of(arguments)
        client = api(environment_row)
        alert = client.alert(identifier, type)
        notes = client.alert_notes(identifier, type, limit: TIMELINE_LIMIT)
        logs = client.alert_logs(identifier, type, limit: TIMELINE_LIMIT)

        [ alert_detail(alert), timeline("Notes, newest first", notes, "note"), timeline("Log, newest first", logs, "log") ].compact.join("\n\n")
      end

      def search_incidents(environment_row:, arguments:)
        query = arguments["query"].to_s.strip
        incidents = api(environment_row).incidents(query: query, limit: Capabilities::Answers.limit(arguments, OpsgenieApi::PAGE_LIMIT, default: INCIDENT_LIMIT))
        return "No Opsgenie incidents match#{" #{query}" if query.present?}." if incidents.empty?

        lines = incidents.map do |incident|
          services = Array(incident["impactedServices"])
          [ "##{incident['tinyId']} #{incident['message']}", "id #{incident['id']}", incident["status"], incident["priority"],
            "created #{incident['createdAt']}", ("#{services.size} services affected" if services.any?) ].compact.join(", ")
        end
        "Opsgenie incidents, newest first:\n#{lines.join("\n")}"
      end

      def acknowledge_alert(environment_row:, arguments:)
        identifier, type = alert_of(arguments)
        accepted = api(environment_row).acknowledge(identifier, type, note: arguments["note"].to_s.strip)
        outcome(environment_row, accepted, "acknowledge alert #{identifier}")
      end

      def escalate_alert(environment_row:, arguments:)
        identifier, type = alert_of(arguments)
        escalation = arguments["escalation"].to_s.strip
        fail! "Name the escalation policy to escalate to, as list_escalations shows it." if escalation.empty?

        accepted = api(environment_row).escalate(identifier, type, escalation: escalation, by_name: !escalation.match?(UUID),
                                                                   note: arguments["note"].to_s.strip)
        outcome(environment_row, accepted, "escalate alert #{identifier} to #{escalation}")
      end

      def add_alert_note(environment_row:, arguments:)
        identifier, type = alert_of(arguments)
        note = arguments["note"].to_s.strip
        fail! "Write the note to add." if note.empty?

        accepted = api(environment_row).add_note(identifier, type, note: note)
        outcome(environment_row, accepted, "add a note to alert #{identifier}")
      end

      def create_alert(environment_row:, arguments:)
        message = arguments["message"].to_s.strip
        fail! "Say what is wrong in message." if message.empty?

        responders = Array(arguments["responders"]).map { |responder| responder_of(responder) }
        fail! "Name who to page in responders." if responders.empty?

        priority = arguments["priority"].presence
        fail! "priority is one of #{OpsgenieApi::PRIORITIES.join(', ')}." if priority && !OpsgenieApi::PRIORITIES.include?(priority)

        accepted = api(environment_row).create_alert(message: message, description: arguments["description"], alias_name: arguments["alias"],
                                                     responders: responders, priority: priority, entity: arguments["entity"])
        outcome(environment_row, accepted, "raise the alert #{message.truncate(60)}")
      end

      def close_alert(environment_row:, arguments:)
        identifier, type = alert_of(arguments)
        accepted = api(environment_row).close(identifier, type, note: arguments["note"].to_s.strip)
        outcome(environment_row, accepted, "close alert #{identifier}")
      end

      def snooze_alert(environment_row:, arguments:)
        identifier, type = alert_of(arguments)
        until_time = time_of(arguments["until"], "until")
        fail! "until is in the past. Give a time still to come." if until_time <= Time.current

        accepted = api(environment_row).snooze(identifier, type, end_time: until_time.utc.iso8601, note: arguments["note"].to_s.strip)
        outcome(environment_row, accepted, "snooze alert #{identifier} until #{until_time.utc.iso8601}")
      end

      def assign_alert(environment_row:, arguments:)
        identifier, type = alert_of(arguments)
        owner = arguments["owner"].to_s.strip
        fail! "Name the owner by their Opsgenie username, their email." if owner.empty?

        accepted = api(environment_row).assign(identifier, type, username: owner, note: arguments["note"].to_s.strip)
        outcome(environment_row, accepted, "make #{owner} the owner of alert #{identifier}")
      end

      def add_responder(environment_row:, arguments:)
        identifier, type = alert_of(arguments)
        kind = arguments["responder_type"].to_s
        fail! "responder_type is team or user." unless %w[team user].include?(kind)

        responder = responder_of("type" => kind, "name" => arguments["responder"])
        accepted = api(environment_row).add_responder(identifier, type, responder: responder, note: arguments["note"].to_s.strip)
        outcome(environment_row, accepted, "add #{kind} #{arguments['responder'].to_s.strip} to alert #{identifier}")
      end

      def resolve_incident(environment_row:, arguments:) = incident_action(environment_row, arguments, :resolve_incident, "resolve")

      def close_incident(environment_row:, arguments:) = incident_action(environment_row, arguments, :close_incident, "close")

      def create_schedule_override(environment_row:, arguments:)
        schedule = arguments["schedule"].to_s.strip
        user = arguments["user"].to_s.strip
        fail! "Name the schedule and who goes on call." if schedule.empty? || user.empty?

        starts = time_of(arguments["start"], "start")
        ends = time_of(arguments["end"], "end")
        fail! "end comes before start. Give an end after the start." unless ends > starts

        made = api(environment_row).create_override(schedule, by_name: !schedule.match?(UUID), username: user,
                                                              start_date: starts.utc.strftime(SCHEDULE_TIME), end_date: ends.utc.strftime(SCHEDULE_TIME))
        override = made["alias"].present? ? ", as override #{made['alias']}" : ""
        "Opsgenie put #{user} on call on #{schedule} from #{starts.utc.iso8601} to #{ends.utc.iso8601}#{override}."
      end

      def create_maintenance(environment_row:, arguments:)
        duration = arguments["duration"].to_s
        fail! "duration is one of #{OpsgenieApi::MAINTENANCE_TIMES.join(', ')}." unless OpsgenieApi::MAINTENANCE_TIMES.include?(duration)

        rules = Array(arguments["targets"]).map { |target| maintenance_rule(target) }
        fail! "Name what to quiet in targets, from list_maintenance_targets." if rules.empty?

        time = { "type" => duration }
        if duration == OpsgenieApi::MAINTENANCE_SCHEDULED
          starts = time_of(arguments["start"], "start")
          ends = time_of(arguments["end"], "end")
          fail! "end comes before start. Give an end after the start." unless ends > starts

          time.merge!("startDate" => starts.utc.strftime(SCHEDULE_TIME), "endDate" => ends.utc.strftime(SCHEDULE_TIME))
        end

        made = api(environment_row).create_maintenance(description: arguments["description"].to_s.strip, time: time, rules: rules)
        span = duration == OpsgenieApi::MAINTENANCE_SCHEDULED ? "from #{time['startDate']} to #{time['endDate']}" : duration.tr("-", " ")
        "Opsgenie started maintenance #{made['id']}, #{made['status'] || 'planned'}, quieting #{rules.size} #{rules.one? ? 'target' : 'targets'} #{span}."
      end

      def check_health!(environment_row)
        api(environment_row).account
      rescue OpsgenieApi::Error => error
        fail! error.message
      end

      private

      def api(environment_row)
        @api ||= begin
          settings = ConnectionSettings.of(environment_row)
          key = settings.credential(API_KEY)
          fail! "This environment has no Opsgenie key. Reconnect it on the Integrations page." if key.nil?

          OpsgenieApi.new(key, region: settings.region&.key)
        end
      end

      def alert_of(arguments)
        identifier = arguments["alert"].to_s.strip
        fail! "Name the alert by its id, tiny id or alias." if identifier.empty?

        type = arguments["identifier_type"].presence || DEFAULT_IDENTIFIER_TYPE
        fail! "identifier_type is one of #{OpsgenieApi::IDENTIFIER_TYPES.join(', ')}." unless OpsgenieApi::IDENTIFIER_TYPES.include?(type)

        [ identifier, type ]
      end

      def on_call_line(name, on_call)
        people = Array(on_call["onCallRecipients"])
        "#{name}: #{people.any? ? people.join(', ') : 'nobody on call'}"
      end

      def escalation_lines(escalation)
        team = escalation.dig("ownerTeam", "name")
        rules = Array(escalation["rules"]).map do |rule|
          recipient = rule["recipient"] || {}
          who = recipient["name"] || recipient["username"] || recipient["id"]
          delay = rule.dig("delay", "timeAmount").to_i
          "- after #{delay} #{rule.dig('delay', 'timeUnit') || 'minutes'}, #{rule['condition']}, notify #{rule['notifyType']} of #{recipient['type']} #{who}"
        end
        [ "#{escalation['name']} (id #{escalation['id']}#{", team #{team}" if team})", *rules ].join("\n")
      end

      def alert_line(alert)
        handled = alert["acknowledged"] ? "acknowledged#{" by #{alert.dig('report', 'acknowledgedBy')}" if alert.dig('report', 'acknowledgedBy')}" : "not acknowledged"
        [ "##{alert['tinyId']} #{alert['message']}", "id #{alert['id']}", alert["status"], handled, alert["priority"],
          "fired #{alert['count']} times", "created #{alert['createdAt']}", ("last #{alert['lastOccurredAt']}" if alert["lastOccurredAt"]),
          ("owner #{alert['owner']}" if alert["owner"].present?), ("source #{alert['source']}" if alert["source"].present?),
          ("tags #{Array(alert['tags']).join(' ')}" if Array(alert["tags"]).any?) ].compact.join(", ")
      end

      def alert_detail(alert)
        report = alert["report"] || {}
        details = (alert["details"] || {}).map { |name, value| "#{name}: #{value}" }
        responders = Array(alert["responders"]).map { |responder| "#{responder['type']} #{responder['name'] || responder['id']}" }
        [
          alert_line(alert),
          ("Entity: #{alert['entity']}" if alert["entity"].present?),
          ("Description: #{alert['description']}" if alert["description"].present?),
          ("Details: #{details.join(', ')}" if details.any?),
          ("Responders: #{responders.join(', ')}" if responders.any?),
          ("Acknowledged after #{report['ackTime'] / 1000} seconds by #{report['acknowledgedBy']}" if report["ackTime"]),
          ("Closed after #{report['closeTime'] / 1000} seconds by #{report['closedBy']}" if report["closeTime"])
        ].compact.join("\n")
      end

      def timeline(title, entries, field)
        return if entries.empty?

        "#{title}:\n#{entries.map { |entry| "#{entry['createdAt']} #{entry['owner']}: #{entry[field]}" }.join("\n")}"
      end

      # Opsgenie does an action a moment after it accepts it, so the answer says whether it was done once Opsgenie
      # says, and that it was accepted when it has not said yet.
      def outcome(environment_row, accepted, what, incident: false)
        request_id = accepted["requestId"]
        return "Opsgenie accepted the request to #{what}." if request_id.blank?

        status = api(environment_row).settle(request_id, incident: incident)
        if status.nil?
          check = incident ? "Check the incident with search_incidents." : "Check the alert with get_alert."
          return "Opsgenie accepted the request to #{what} and has not said yet whether it is done. #{check}"
        end
        return Sentence.join("Opsgenie did #{what}", status["status"]) if status["isSuccess"]

        fail! Sentence.join("Opsgenie could not #{what}", status["status"])
      end

      def incident_action(environment_row, arguments, call, verb)
        identifier = arguments["incident"].to_s.strip
        fail! "Name the incident by its id or tiny id." if identifier.empty?

        type = arguments["identifier_type"].presence || DEFAULT_IDENTIFIER_TYPE
        fail! "identifier_type is id or tiny." unless %w[id tiny].include?(type)

        accepted = api(environment_row).public_send(call, identifier, type, note: arguments["note"].to_s.strip)
        outcome(environment_row, accepted, "#{verb} incident #{identifier}", incident: true)
      end

      # A responder as Opsgenie takes it: a user by their username, anything else by its name, or by its id when the
      # name is one.
      def responder_of(given)
        responder = given.to_h.stringify_keys
        type = responder["type"].to_s
        name = responder["name"].to_s.strip
        fail! "Each responder is a #{OpsgenieApi::RESPONDER_TYPES.join(', ')} with its name." unless OpsgenieApi::RESPONDER_TYPES.include?(type) && name.present?
        return { "type" => type, "username" => name } if type == "user"

        { "type" => type, (name.match?(UUID) ? "id" : "name") => name }
      end

      # A rule turns its target off for the window. Opsgenie takes nothing else for an integration.
      def maintenance_rule(target)
        given = target.to_h.stringify_keys
        type = given["type"].to_s
        id = given["id"].to_s.strip
        fail! "Each target is an integration or a policy with its id." unless OpsgenieApi::MAINTENANCE_ENTITIES.include?(type) && id.present?

        { "state" => "disabled", "entity" => { "id" => id, "type" => type } }
      end

      def time_of(value, name)
        Time.iso8601(value.to_s.strip)
      rescue ArgumentError
        fail! "#{name} is a time in ISO 8601, such as 2026-10-11T09:30:00Z."
      end
    end
  end
end
