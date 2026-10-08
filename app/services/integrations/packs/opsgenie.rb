module Integrations
  module Packs
    # Opsgenie, read with the key of an API integration the workspace creates in Opsgenie: who is on call, the
    # escalations that page people, and the alerts and incidents open now. Acknowledging, escalating and adding a note to
    # an alert change Opsgenie, so a member needs a grant for them, they ask before they run in a chat and they are never
    # used while investigating. Opsgenie's API gives no page address for anything it returns and documents none, so
    # results carry no link. The executor hides anything that looks like a credential in what comes back.
    class Opsgenie < NativePack
      # The one credential this pack keeps. It has no plain settings to ask for.
      API_KEY = "api_key".freeze

      ALERT_LIMIT = 20
      INCIDENT_LIMIT = 20
      TIMELINE_LIMIT = 20
      SCHEDULES_SHOWN = 25
      # How often, and how long apart, an action Opsgenie accepted is checked for whether it was done.
      STATUS_CHECKS = 3
      STATUS_WAIT = 1
      UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
      DEFAULT_IDENTIFIER_TYPE = OpsgenieApi::IDENTIFIER_TYPES.first

      ALERT = {
        "alert" => { "type" => "string", "description" => "The alert, by its id, its tiny id (the short number Opsgenie shows) or its alias" },
        "identifier_type" => { "type" => "string", "enum" => OpsgenieApi::IDENTIFIER_TYPES,
                               "description" => "Which of these alert names: id, tiny or alias (optional, id). An alias only finds an open alert" }
      }.freeze
      NOTE = { "type" => "string", "description" => "A note Opsgenie adds to the alert, saying why (optional)" }.freeze

      tool :who_is_on_call,
           description: "Who is on call now in Opsgenie, for one schedule or for every schedule with the team that owns it. Use it to " \
                        "find who to page or who is already being paged",
           params_schema: {
             "type" => "object",
             "properties" => {
               "schedule" => { "type" => "string", "description" => "One schedule, by its name or id (optional, every schedule)" }
             }
           },
           read_only: true

      tool :list_escalations,
           description: "The escalation policies in Opsgenie: who each one notifies, in what order, after how long and on which " \
                        "condition. Use it to see who an alert reaches next, and for the name escalate_alert takes",
           params_schema: { "type" => "object", "properties" => {} },
           read_only: true

      tool :search_alerts,
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
           description: "One Opsgenie alert in full: its message, description, details, tags, responders and how it was handled, " \
                        "with its latest notes and its log of what happened to it",
           params_schema: { "type" => "object", "properties" => ALERT, "required" => [ "alert" ] },
           read_only: true

      tool :search_incidents,
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

      tool :acknowledge_alert,
           description: "Acknowledge an Opsgenie alert, which stops it paging further along its escalation. Say who is handling it " \
                        "in the note",
           params_schema: { "type" => "object", "properties" => ALERT.merge("note" => NOTE), "required" => [ "alert" ] },
           read_only: false

      tool :escalate_alert,
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
           description: "Add a note to an Opsgenie alert, which everyone on it sees, such as what is known or which incident it belongs to",
           params_schema: {
             "type" => "object",
             "properties" => ALERT.merge("note" => { "type" => "string", "description" => "The note to add" }),
             "required" => [ "alert", "note" ]
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

      # Opsgenie does an alert action a moment after it accepts it, so the answer says whether it was done once
      # Opsgenie says, and that it was accepted when it has not said yet.
      def outcome(environment_row, accepted, what)
        request_id = accepted["requestId"]
        return "Opsgenie accepted the request to #{what}." if request_id.blank?

        STATUS_CHECKS.times do |check|
          sleep(STATUS_WAIT) if check.positive?
          status = api(environment_row).request_status(request_id)
          next if status.blank?
          return Sentence.join("Opsgenie did #{what}", status["status"]) if status["isSuccess"]

          fail! Sentence.join("Opsgenie could not #{what}", status["status"])
        rescue OpsgenieApi::Error
          next
        end
        "Opsgenie accepted the request to #{what} and has not said yet whether it is done. Check the alert with get_alert."
      end
    end
  end
end
