module Integrations
  # Calls to DigitalOcean's API with a workspace's own personal access token, for the DigitalOcean integration. Paths,
  # parameters and answers are the ones in DigitalOcean's OpenAPI specification (digitalocean/openapi,
  # specification/DigitalOcean-public.v2.yaml and specification/resources/{apps,droplets,databases,monitoring}).
  class DigitaloceanApi
    class Error < Integrations::Error; end
    # DigitalOcean answered that what was named is not there, such as a deployment of another app.
    class NotFound < Error
      include Integrations::NotFound
    end
    REFINE = ->(code, _reason) { NotFound if code == 404 }
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
    # How long a live log address is read before what it sent so far is taken.
    LIVE_SECONDS = 10
    JOB_INVOCATION_LOGS = "JOB_INVOCATION".freeze
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

    # One deployment with its progress, steps and the phase it is in (apps_get_deployment).
    def deployment(app_id, deployment_id) = get("/apps/#{Http.segment(app_id)}/deployments/#{Http.segment(deployment_id)}")["deployment"] || {}

    def health(app_id) = get("/apps/#{Http.segment(app_id)}/health")["app_health"] || {}

    # Where the logs of one deployment are, the active one unless named, of one component or of every one
    # (apps_get_logs_active_deployment, apps_get_logs and their aggregate forms): the archived files (historic_urls), and
    # for a deployment still running or serving, its live address (live_url). Asked without follow, the live address sends
    # what is there now and closes, as doctl reads it (digitalocean/doctl, commands/apps.go, RunAppsGetLogs).
    def logs(app_id, type:, component: nil, deployment: nil)
      path = "/apps/#{Http.segment(app_id)}"
      path += "/deployments/#{Http.segment(deployment)}" if deployment
      path += "/components/#{Http.segment(component)}" if component
      log_answer(get("#{path}/logs", "type" => type, "follow" => false))
    end

    # Where one job invocation's logs are (apps_get_job_invocation_logs), by its job's name, in the same shape.
    def job_invocation_logs(app_id, job_name, invocation_id)
      path = "/apps/#{Http.segment(app_id)}/jobs/#{Http.segment(job_name)}/invocations/#{Http.segment(invocation_id)}/logs"
      log_answer(get(path, "type" => JOB_INVOCATION_LOGS, "follow" => false))
    end

    # One archived log file at DigitalOcean's signed address, read without the token, which only ever goes to the API,
    # on a public https address only, and cut to its last LOG_BYTES.
    def log_file(url) = Http.download(url, provider_key: PROVIDER_KEY, error_class: Error, limit: LOG_BYTES)

    # What a live log address holds now, read the same way as a file and for at most LIVE_SECONDS. Each message is JSON
    # with its lines in data, as doctl reads it.
    def live_log(url)
      Http::LiveSocket.messages(url, provider_key: PROVIDER_KEY, error_class: Error, limit: LOG_BYTES, seconds: LIVE_SECONDS).map do |message|
        parsed = JSON.parse(message)
        parsed.is_a?(Hash) ? parsed["data"].to_s : message
      rescue JSON::ParserError
        message
      end.join
    end

    def rollback(app_id, deployment_id) = post("/apps/#{Http.segment(app_id)}/rollback", { "deployment_id" => deployment_id })

    # Whether the app can go back to a deployment, with the condition that stops it (error) and the ones that make it
    # slower or less exact (warnings), each a code, a message and its components (apps_validate_rollback).
    def validate_rollback(app_id, deployment_id) = post("/apps/#{Http.segment(app_id)}/rollback/validate", { "deployment_id" => deployment_id })

    # Keeps the rollback for good and unpins the app (apps_commit_rollback).
    def commit_rollback(app_id) = post("/apps/#{Http.segment(app_id)}/rollback/commit", nil)

    # Undoes the rollback with a new deployment of the spec from before it, and unpins the app (apps_revert_rollback).
    def revert_rollback(app_id) = post("/apps/#{Http.segment(app_id)}/rollback/revert", nil)

    # A new deployment from the newest commit of each component's source, built again from scratch with force_build
    # (apps_create_deployment).
    def create_deployment(app_id, force_build:) = post("/apps/#{Http.segment(app_id)}/deployments", { "force_build" => force_build })

    def cancel_deployment(app_id, deployment_id)
      post("/apps/#{Http.segment(app_id)}/deployments/#{Http.segment(deployment_id)}/cancel", nil)["deployment"] || {}
    end

    # An app's job invocations, newest first, of one job or every one (apps_list_job_invocations).
    def job_invocations(app_id, limit:, job_name: nil)
      get("/apps/#{Http.segment(app_id)}/job-invocations", { "per_page" => limit, "job_names" => job_name })["job_invocations"] || []
    end

    # One job invocation (apps_get_job_invocation), which the specification shows both bare and under job_invocation.
    def job_invocation(app_id, invocation_id)
      answer = get("/apps/#{Http.segment(app_id)}/job-invocations/#{Http.segment(invocation_id)}")
      answer["job_invocation"] || answer
    end

    def cancel_job_invocation(app_id, invocation_id, job_name:)
      answer = send_request(:post, "/apps/#{Http.segment(app_id)}/job-invocations/#{Http.segment(invocation_id)}/cancel", nil, { "job_name" => job_name })
      answer["job_invocation"] || answer
    end

    # An app's events, its deployments and autoscaling, newest first (apps_list_events).
    # One event (apps_get_event), and cancelling an autoscaling one still going (apps_cancel_event), each under event.
    def event(app_id, event_id) = get("/apps/#{Http.segment(app_id)}/events/#{Http.segment(event_id)}")["event"] || {}

    def cancel_event(app_id, event_id) = post("/apps/#{Http.segment(app_id)}/events/#{Http.segment(event_id)}/cancel", nil)["event"] || {}

    def events(app_id, limit:, type: nil) =get("/apps/#{Http.segment(app_id)}/events", { "per_page" => limit, "event_types" => type })["events"] || []

    # The alerts an app and its components have set up, each a rule, its threshold and its phase (apps_list_alerts).
    def alerts(app_id) = get("/apps/#{Http.segment(app_id)}/alerts")["alerts"] || []

    # components empty restarts every one, as the API does when none is named.
    def restart(app_id, components = []) = post("/apps/#{Http.segment(app_id)}/restart", components.any? ? { "components" => components } : {})

    def update_app(app_id, spec) = send_request(:put, "/apps/#{Http.segment(app_id)}", { "spec" => spec })

    def droplets = list("/droplets", "droplets")

    def droplet(droplet_id) = get("/droplets/#{Http.segment(droplet_id)}")["droplet"] || {}

    def droplet_action(droplet_id, type) = post("/droplets/#{Http.segment(droplet_id)}/actions", { "type" => type })

    # A Droplet's actions, such as reboots, resizes and power cycles, each with its status and when it started and ended
    # (dropletActions_list). The specification gives no order, so the first page and the last are read and the newest of
    # both taken.
    def droplet_actions(droplet_id, limit:)
      path = "/droplets/#{Http.segment(droplet_id)}/actions"
      first = get(path, "per_page" => PAGE_SIZE, "page" => 1)
      last = first.dig("links", "pages", "last").to_s[/[?&]page=(\d+)/, 1].to_i
      found = Array(first["actions"]) + (last > 1 ? Array(get(path, "per_page" => PAGE_SIZE, "page" => last)["actions"]) : [])
      found.uniq { |action| action["id"] }.sort_by { |action| action["started_at"].to_s }.reverse.first(limit)
    end

    # The list takes no page parameters in the specification, so it is read as one answer, and always in full.
    def databases = Pages::Read.new(items: get("/databases")["databases"] || [], complete: true)

    def database(database_id) = get("/databases/#{Http.segment(database_id)}")["database"] || {}

    # A metric under /monitoring/metrics, such as apps/cpu_percentage, as the series DigitalOcean answers with.
    def metrics(path, query) = get("/monitoring/metrics/#{path}", query).dig("data", "result") || []

    # Any GET of the API by its path as the specification writes it, /v2 included, for the general read
    # (Integrations::ApiReads), which checks the path before it gets here.
    def read(path, query) = send_request(:get, path.delete_prefix(API_PREFIX), nil, query)

    # What the account owes and has used this month (customers/my/balance): month_to_date_usage, month_to_date_balance,
    # account_balance and generated_at, each amount a string of dollars.
    def balance = get("/customers/my/balance")

    # The monthly invoices, newest first, and invoice_preview, the month so far (customers/my/invoices), each with
    # invoice_uuid, amount and invoice_period as YYYY-MM.
    def invoices(limit:) = get("/customers/my/invoices", "per_page" => limit)

    # One invoice's charges by product (customers/my/invoices/{uuid}/summary, product_charges.items), each with name and amount.
    def invoice_summary(invoice_uuid) = get("/customers/my/invoices/#{Http.segment(invoice_uuid)}/summary")

    private

    def log_answer(answer) = { historic: Array(answer["historic_urls"]), live: answer["live_url"].presence }

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
      Http.json(uri, request, error_class: Error, provider_name: PROVIDER, reason: REASON, refine: REFINE)
    end
  end
end
