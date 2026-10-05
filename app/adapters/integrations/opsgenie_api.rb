module Integrations
  # Calls to Opsgenie's REST API with a workspace's own API integration key, for the Opsgenie integration. Every path,
  # parameter and field here is from Opsgenie's API documentation (docs.opsgenie.com: Authentication, Account API, Who
  # is On Call API, Schedule API, Escalation API, Alert API and Incident API). An account lives on the US or the EU
  # instance, named by the registry's region keys, and a key only works on its own (Atlassian support, European service
  # region).
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

    def escalations = Array(get("/v2/escalations")["data"])

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

    # Whether an action Opsgenie accepted was done, and what it said about it.
    def request_status(request_id) = get("/v2/alerts/requests/#{segment(request_id)}")["data"] || {}

    private

    def act(identifier, type, action, body)
      uri = URI.parse("#{@root}/v2/alerts/#{segment(identifier)}/#{action}")
      uri.query = URI.encode_www_form("identifierType" => type)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = body.merge("source" => SOURCE).compact.to_json
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
