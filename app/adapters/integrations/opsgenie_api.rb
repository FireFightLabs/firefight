module Integrations
  # Calls to Opsgenie's REST API with a workspace's own API integration key, for the Opsgenie integration. Every path,
  # parameter and field here is from Opsgenie's API documentation (docs.opsgenie.com: Authentication, Account API, Who
  # is On Call API, Schedule API, Schedule Override API, Escalation API, Alert API, Incident API, Maintenance API,
  # Integration API and Policy API). An account lives on the US or the EU instance, named by the registry's region keys,
  # and a key only works on its own (Atlassian support, European service region).
  class OpsgenieApi
    class Error < Integrations::Error; end
    # The key is wrong for this instance, or the integration behind it is turned off.
    class Unauthenticated < Error; end

    REGION_US = "us".freeze
    REGION_EU = "eu".freeze
    ROOTS = { REGION_US => "https://api.opsgenie.com", REGION_EU => "https://api.eu.opsgenie.com" }.freeze
    IDENTIFIER_TYPES = %w[id tiny alias].freeze
    PAGE_LIMIT = 100
    SOURCE = "Firefight".freeze
    UNAUTHENTICATED = 401
    # The kinds of responder an alert can be sent to.
    RESPONDER_TYPES = %w[team user escalation schedule].freeze
    PRIORITIES = %w[P1 P2 P3 P4 P5].freeze
    MESSAGE_LIMIT = 130
    DESCRIPTION_LIMIT = 15_000
    # The lengths of time a maintenance window can run for without dates, and the one that takes them.
    MAINTENANCE_SCHEDULED = "schedule".freeze
    MAINTENANCE_TIMES = [ "for-5-minutes", "for-30-minutes", "for-1-hour", "indefinitely", MAINTENANCE_SCHEDULED ].freeze
    MAINTENANCE_ENTITIES = %w[integration policy].freeze
    # How often, and how many seconds apart, a request Opsgenie accepted is asked about.
    SETTLE_CHECKS = 3
    SETTLE_WAIT = 1

    # region is the registry's region key. A connection made before regions were listed has none, and reached the US.
    def initialize(api_key, region: nil)
      @api_key = api_key
      @root = ROOTS.fetch(region.presence || REGION_US) { raise Error, "Opsgenie has no #{region} instance" }
    end

    def account = get("/v2/account")["data"] || {}

    def schedules = Array(get("/v2/schedules")["data"])

    # flat names the people on call rather than the rules that put them there.
    def on_calls(schedule, by_name:)
      get("/v2/schedules/#{segment(schedule)}/on-calls", "scheduleIdentifierType" => by_name ? "name" : "id", "flat" => "true")["data"] || {}
    end

    # Who comes on call next on the schedule, by the people's usernames.
    def next_on_calls(schedule, by_name:)
      get("/v2/schedules/#{segment(schedule)}/next-on-calls", "scheduleIdentifierType" => by_name ? "name" : "id", "flat" => "true")["data"] || {}
    end

    # Puts user on call on the schedule between the two times, which Opsgenie reads as yyyy-MM-dd'T'HH:mm:ssZ.
    def create_override(schedule, by_name:, username:, start_date:, end_date:)
      body = { "user" => { "type" => "user", "username" => username }, "startDate" => start_date, "endDate" => end_date }
      post("/v2/schedules/#{segment(schedule)}/overrides", { "scheduleIdentifierType" => by_name ? "name" : "id" }, body)["data"] || {}
    end

    def escalations = Array(get("/v2/escalations")["data"])

    def integrations = Array(get("/v2/integrations")["data"])

    def alert_policies = Array(get("/v2/policies/alert")["data"])

    # Stops the rules from acting for a while, an integration's alerts or a policy's actions.
    def create_maintenance(description:, time:, rules:)
      post("/v1/maintenance", {}, { "description" => description.presence, "time" => time, "rules" => rules }.compact)["data"] || {}
    end

    def alerts(query:, limit:)
      Array(get("/v2/alerts", "query" => query.presence, "limit" => limit.clamp(1, PAGE_LIMIT), "sort" => "createdAt", "order" => "desc")["data"])
    end

    def alert(identifier, type) = get("/v2/alerts/#{segment(identifier)}", "identifierType" => type)["data"] || {}

    def alert_notes(identifier, type, limit:)
      Array(get("/v2/alerts/#{segment(identifier)}/notes", "identifierType" => type, "limit" => limit, "order" => "desc")["data"])
    end

    def alert_logs(identifier, type, limit:)
      Array(get("/v2/alerts/#{segment(identifier)}/logs", "identifierType" => type, "limit" => limit, "order" => "desc")["data"])
    end

    def incidents(query:, limit:)
      Array(get("/v1/incidents", "query" => query.presence, "limit" => limit.clamp(1, PAGE_LIMIT), "sort" => "createdAt", "order" => "desc")["data"])
    end

    # Opsgenie takes an alert action and answers 202 with a request id, then does it a moment later.
    def acknowledge(identifier, type, note:) = act(identifier, type, "acknowledge", "note" => note.presence)

    def escalate(identifier, type, escalation:, by_name:, note:)
      act(identifier, type, "escalate", "escalation" => { (by_name ? "name" : "id") => escalation }, "note" => note.presence)
    end

    def add_note(identifier, type, note:) = act(identifier, type, "notes", "note" => note)

    def close(identifier, type, note:) = act(identifier, type, "close", "note" => note.presence)

    # end_time is when it pages again, as ISO 8601.
    def snooze(identifier, type, end_time:, note:) = act(identifier, type, "snooze", "endTime" => end_time, "note" => note.presence)

    def assign(identifier, type, username:, note:) = act(identifier, type, "assign", "owner" => { "username" => username }, "note" => note.presence)

    # responder is { "type" => "team" or "user", and "name", "id" or "username" }.
    def add_responder(identifier, type, responder:, note:) = act(identifier, type, "responders", "responder" => responder, "note" => note.presence)

    # Raises an alert, which pages the responders through their escalations and schedules. alias_name keeps a second
    # create from making a second open alert.
    def create_alert(message:, description:, alias_name:, responders:, priority: nil, entity: nil, note: nil)
      body = { "message" => message.to_s.truncate(MESSAGE_LIMIT), "description" => description.to_s.truncate(DESCRIPTION_LIMIT).presence,
               "alias" => alias_name.presence, "responders" => responders.presence, "priority" => priority.presence,
               "entity" => entity.presence, "note" => note.presence, "source" => SOURCE }.compact
      post("/v2/alerts", {}, body)
    end

    def resolve_incident(identifier, type, note:) = post("/v1/incidents/#{segment(identifier)}/resolve", { "identifierType" => type }, { "note" => note.presence }.compact)

    def close_incident(identifier, type, note:) = post("/v1/incidents/#{segment(identifier)}/close", { "identifierType" => type }, { "note" => note.presence }.compact)

    # Whether an action Opsgenie accepted was done, and what it said about it.
    def request_status(request_id) = get("/v2/alerts/requests/#{segment(request_id)}")["data"] || {}

    def incident_request_status(request_id) = get("/v1/incidents/requests/#{segment(request_id)}")["data"] || {}

    # What Opsgenie said of a request it accepted, asked up to SETTLE_CHECKS times a second apart, or nil while it has
    # not said. A request it does not know yet is asked again.
    def settle(request_id, incident: false)
      SETTLE_CHECKS.times do |check|
        sleep(SETTLE_WAIT) if check.positive?
        status = incident ? incident_request_status(request_id) : request_status(request_id)
        return status if status.present?
      rescue Error
        next
      end
      nil
    end

    private

    def act(identifier, type, action, body)
      post("/v2/alerts/#{segment(identifier)}/#{action}", { "identifierType" => type }, body.merge("source" => SOURCE).compact)
    end

    def post(path, query, body)
      uri = URI.parse("#{@root}#{path}")
      uri.query = URI.encode_www_form(query) if query.any?
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = body.to_json
      send_request(uri, request)
    end

    def get(path, query = {})
      uri = URI.parse("#{@root}#{path}")
      pairs = query.compact
      uri.query = URI.encode_www_form(pairs) if pairs.any?
      send_request(uri, Net::HTTP::Get.new(uri))
    end

    def send_request(uri, request)
      request["Authorization"] = "GenieKey #{@api_key}"
      Http.json(uri, request, error_class: Error, provider_name: "Opsgenie", refine: ->(code, _said) { Unauthenticated if code == UNAUTHENTICATED })
    end

    def segment(value) = Http.segment(value)
  end
end
