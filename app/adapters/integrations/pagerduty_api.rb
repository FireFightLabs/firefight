module Integrations
  # Calls to PagerDuty's REST API v2 with the connection's own credentials, the OAuth token or user API key its MCP
  # server is reached with, for raising a page and keeping it in step. PagerDuty documents the hosted server's tools and
  # their actions but not their arguments, while every path, header and field here is in its REST API reference
  # (PagerDuty/api-schema, reference/REST/openapiv3.json). Each region has its own API, as it has its own server.
  class PagerdutyApi
    class Error < Integrations::Error; end

    REGION_US = "us".freeze
    REGION_EU = "eu".freeze
    ROOTS = { REGION_US => "https://api.pagerduty.com", REGION_EU => "https://api.eu.pagerduty.com" }.freeze
    ACCEPT = "application/vnd.pagerduty+json;version=2".freeze
    STATUS_TRIGGERED = "triggered".freeze
    STATUS_ACKNOWLEDGED = "acknowledged".freeze
    STATUS_RESOLVED = "resolved".freeze
    TITLE_LIMIT = 1024
    PAGE_LIMIT = 100

    # headers carry the connection's Authorization. region is the registry's region key, the US when it names none.
    def initialize(headers, region: nil)
      @headers = headers.to_h
      @root = ROOTS.fetch(region.presence || REGION_US) { raise Error, "PagerDuty has no #{region} service region" }
    end

    # Services whose name matches query, as PagerDuty searches them.
    def services(query:) = Array(get("/services", "query" => query.presence, "limit" => PAGE_LIMIT)["services"])

    def service(id) = get("/services/#{segment(id)}")["service"] || {}

    # Opens an incident on the service, which pages whoever its escalation policy names. incident_key makes a retry
    # land on the same open incident rather than a second one. The change is made as the user the token belongs to,
    # which an OAuth token and a user API key name, so no From header is sent.
    def create_incident(service_id:, title:, details:, incident_key:)
      body = { "incident" => {
        "type" => "incident", "title" => title.to_s.truncate(TITLE_LIMIT),
        "service" => { "id" => service_id, "type" => "service_reference" },
        "body" => { "type" => "incident_body", "details" => details.to_s },
        "incident_key" => incident_key
      } }
      send_json(Net::HTTP::Post, "/incidents", body)["incident"] || {}
    end

    def incident(id) = get("/incidents/#{segment(id)}")["incident"] || {}

    # Moves the incident to acknowledged or resolved.
    def update_status(id, status:)
      body = { "incident" => { "type" => "incident_reference", "status" => status } }
      send_json(Net::HTTP::Put, "/incidents/#{segment(id)}", body)["incident"] || {}
    end

    # Who is on call now, the earliest on-call of each person at each level of each escalation policy, with each user's
    # email.
    def on_calls
      Array(get("/oncalls", "include[]" => "users", "earliest" => "true", "limit" => PAGE_LIMIT)["oncalls"])
    end

    private

    def get(path, query = {})
      uri = URI.parse("#{@root}#{path}")
      pairs = query.compact
      uri.query = URI.encode_www_form(pairs) if pairs.any?
      send_request(uri, Net::HTTP::Get.new(uri))
    end

    def send_json(verb, path, body)
      uri = URI.parse("#{@root}#{path}")
      request = verb.new(uri)
      request["Content-Type"] = "application/json"
      request.body = body.to_json
      send_request(uri, request)
    end

    def send_request(uri, request)
      @headers.each { |name, value| request[name] = value }
      request["Accept"] = ACCEPT
      Http.json(uri, request, error_class: Error, provider_name: "PagerDuty", reason: method(:reason))
    end

    # PagerDuty's error is { error: { message, errors: [...] } }, and the list says which field was wrong.
    def reason(body)
      error = body["error"]
      return Http::REASON.call(body) unless error.is_a?(Hash)

      [ error["message"], *Array(error["errors"]) ].compact_blank.uniq.join(". ")
    end

    def segment(value) = Http.segment(value)
  end
end
