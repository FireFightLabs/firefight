module Integrations
  # Calls to DigitalOcean's API with a workspace's own personal access token, for the DigitalOcean integration. Paths,
  # parameters and answers are the ones in DigitalOcean's OpenAPI specification (digitalocean/openapi,
  # specification/DigitalOcean-public.v2.yaml and specification/resources/{apps,droplets,databases,monitoring}).
  class DigitaloceanApi
    class Error < Integrations::Error; end
    # The provider this client calls, by its registry key and name, for the address check and its errors.
    PROVIDER_KEY = "digitalocean".freeze
    PROVIDER = "DigitalOcean".freeze
    VERBS = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.freeze

    API_HOST = "api.digitalocean.com".freeze
    API_PREFIX = "/v2".freeze
    API_ROOT = "https://#{API_HOST}#{API_PREFIX}".freeze
    # The most per_page allows, and how many pages a list reads before it stops.
    PAGE_SIZE = 200
    MAX_PAGES = 10
    LOG_BYTES = 2_000_000
    # DigitalOcean puts its reason in message, and its error's name in id.
    REASON = ->(body) { body["message"].presence || body["id"].presence }

    def initialize(token)
      @token = token
    end

    def account = get("/account")["account"] || {}

    # A list of apps or Droplets is read up to MAX_PAGES and says whether it read all of them (Integrations::Pages::Read).
    def apps = list("/apps", "apps")

    def app(app_id) = get("/apps/#{Http.segment(app_id)}")["app"] || {}

    def deployments(app_id, limit:) = get("/apps/#{Http.segment(app_id)}/deployments", "per_page" => limit)["deployments"] || []

    def health(app_id) = get("/apps/#{Http.segment(app_id)}/health")["app_health"] || {}

    # The archived logs of the active deployment, of one component or of every one. DigitalOcean answers with the
    # addresses of the files (historic_urls), which are read next, and a live address Firefight does not follow.
    def log_urls(app_id, type:, component: nil)
      path = component ? "/apps/#{Http.segment(app_id)}/components/#{Http.segment(component)}/logs" : "/apps/#{Http.segment(app_id)}/logs"
      Array(get(path, "type" => type, "follow" => false)["historic_urls"])
    end

    # One archived log file at DigitalOcean's signed address, read without the token, which only ever goes to the API,
    # on a public https address only, and cut to its last LOG_BYTES.
    def log_file(url) = Http.download(url, provider_key: PROVIDER_KEY, error_class: Error, limit: LOG_BYTES)

    def rollback(app_id, deployment_id) = post("/apps/#{Http.segment(app_id)}/rollback", { "deployment_id" => deployment_id })

    # components empty restarts every one, as the API does when none is named.
    def restart(app_id, components = []) = post("/apps/#{Http.segment(app_id)}/restart", components.any? ? { "components" => components } : {})

    def update_app(app_id, spec) = send_request(:put, "/apps/#{Http.segment(app_id)}", { "spec" => spec })

    def droplets = list("/droplets", "droplets")

    def droplet(droplet_id) = get("/droplets/#{Http.segment(droplet_id)}")["droplet"] || {}

    def droplet_action(droplet_id, type) = post("/droplets/#{Http.segment(droplet_id)}/actions", { "type" => type })

    # The list takes no page parameters in the specification, so it is read as one answer, and always in full.
    def databases = Pages::Read.new(items: get("/databases")["databases"] || [], complete: true)

    def database(database_id) = get("/databases/#{Http.segment(database_id)}")["database"] || {}

    # A metric under /monitoring/metrics, such as apps/cpu_percentage, as the series DigitalOcean answers with.
    def metrics(path, query) = get("/monitoring/metrics/#{path}", query).dig("data", "result") || []

    # Any GET of the API by its path as the specification writes it, /v2 included, for the general read
    # (Integrations::ApiReads), which checks the path before it gets here.
    def read(path, query) = send_request(:get, path.delete_prefix(API_PREFIX), nil, query)

    private

    # Every page of a list, following DigitalOcean's links.pages.next, up to MAX_PAGES.
    def list(path, key)
      Pages.read(max_pages: MAX_PAGES) do |page|
        number = page || 1
        body = get(path, "per_page" => PAGE_SIZE, "page" => number)
        [ body[key], (number + 1 if body.dig("links", "pages", "next").present?) ]
      end
    end

    def get(path, query = {}) = send_request(:get, path, nil, query)

    def post(path, body) = send_request(:post, path, body)

    def send_request(verb, path, body = nil, query = {})
      uri = URI.parse("#{API_ROOT}#{path}")
      uri.query = URI.encode_www_form(query.compact.transform_values(&:to_s)) if query.compact.any?
      request = VERBS.fetch(verb).new(uri)
      request["Authorization"] = "Bearer #{@token}"
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      Http.json(uri, request, error_class: Error, provider_name: PROVIDER, reason: REASON)
    end
  end
end
