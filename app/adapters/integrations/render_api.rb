module Integrations
  # Calls to Render's public REST API with a workspace's own API key, for the Render integration. Paths, parameters
  # and answers are the ones in Render's OpenAPI spec (api-docs.render.com/openapi/render-public-api-1.json), with list
  # parameters encoded as the Go client generated from it does (render-oss/render-mcp-server, pkg/client/client_gen.go).
  class RenderApi
    class Error < Integrations::Error; end
    # Asked too often, so a caller making many calls stops rather than keep being refused.
    class RateLimited < Error; end

    API_ROOT = "https://api.render.com/v1".freeze
    TOO_MANY_REQUESTS = 429
    # Render answers at most this many rows a page, and a list is read for at most this many pages.
    PAGE_SIZE = 100
    MAX_PAGES = 10

    def initialize(api_key)
      @api_key = api_key
    end

    def owner(owner_id) = get("/owners/#{segment(owner_id)}")

    # Every service, Postgres database and Key Value instance in the workspace. ownerId is comma separated, as the spec's
    # form style without explode asks.
    def services(owner_id) = list("/services", "service", "ownerId" => owner_id)

    def postgres_databases(owner_id) = list("/postgres", "postgres", "ownerId" => owner_id)

    def key_values(owner_id) = list("/key-value", "keyValue", "ownerId" => owner_id)

    def service(service_id) = get("/services/#{segment(service_id)}")

    def postgres(postgres_id) = get("/postgres/#{segment(postgres_id)}")

    def key_value(key_value_id) = get("/key-value/#{segment(key_value_id)}")

    def deploys(service_id, limit:) = page("/services/#{segment(service_id)}/deploys", "deploy", "limit" => limit)

    def custom_domains(service_id) = list("/services/#{segment(service_id)}/custom-domains", "customDomain")

    def events(service_id, query) = page("/services/#{segment(service_id)}/events", "event", query)

    # One page of log lines. ownerId and resource are required, and every list filter is sent once per value.
    def logs(query) = get("/logs", query)

    # One time series per label set, for metrics such as cpu, memory or http-requests.
    def metrics(name, query) = Array(get("/metrics/#{name}", query))

    def restart_service(service_id) = post("/services/#{segment(service_id)}/restart")

    def restart_postgres(postgres_id) = post("/postgres/#{segment(postgres_id)}/restart")

    def rollback(service_id, deploy_id) = post("/services/#{segment(service_id)}/rollback", "deployId" => deploy_id)

    def scale(service_id, instances) = post("/services/#{segment(service_id)}/scale", "numInstances" => instances)

    private

    # Every page of a list, which Render answers as an array of { cursor, <key> } pairs, up to MAX_PAGES.
    def list(path, key, query = {})
      rows = []
      cursor = nil
      MAX_PAGES.times do
        answered = Array(get(path, query.merge("limit" => PAGE_SIZE, "cursor" => cursor)))
        rows.concat(answered.filter_map { |pair| pair[key] })
        cursor = answered.last&.dig("cursor")
        break if answered.size < PAGE_SIZE || cursor.blank?
      end
      rows
    end

    def page(path, key, query) = Array(get(path, query)).filter_map { |pair| pair[key] }

    def get(path, query = {})
      uri = URI.parse("#{API_ROOT}#{path}")
      encoded = encode(query)
      uri.query = encoded if encoded.present?
      send_request(uri, Net::HTTP::Get.new(uri))
    end

    def post(path, body = nil)
      uri = URI.parse("#{API_ROOT}#{path}")
      request = Net::HTTP::Post.new(uri)
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      send_request(uri, request)
    end

    def send_request(uri, request)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Accept"] = "application/json"
      response = Http.request(uri, request, error_class: Error, read_timeout: 30)
      succeeded = response.code.to_i.between?(200, 299)
      body = response.body.to_s.strip.empty? ? {} : JSON.parse(response.body)
      return body if succeeded

      reason = (body["message"] if body.is_a?(Hash)).presence || "no reason given"
      raise (response.code.to_i == TOO_MANY_REQUESTS ? RateLimited : Error), "Render answered #{response.code}: #{reason}"
    rescue JSON::ParserError
      # A change that went through stays one that went through, whatever came back with it.
      return {} if succeeded

      raise Error, "Render answered #{response.code} with something that is not JSON"
    end

    # A list value is sent once per value (resource=a&resource=b), which is how /logs and /metrics read one.
    def encode(query)
      pairs = query.compact.flat_map { |name, value| Array(value).map { |each| [ name.to_s, each.to_s ] } }
      URI.encode_www_form(pairs)
    end

    def segment(value) = ERB::Util.url_encode(value.to_s)
  end
end
