module Integrations
  # Calls to Northflank's API with a workspace's own token, for the Northflank integration. request is any call inside
  # the project, which the api_request tool sends. The code sandbox has its own client, since it runs on Firefight's token.
  class NorthflankApi
    class Error < Integrations::Error; end
    # Asked too often, so a caller making many calls stops rather than keep being refused.
    class RateLimited < Error
      include Integrations::RateLimited
    end
    # Northflank keeps some data behind features an account has to have switched on, and says so with a 401 that has
    # nothing to do with the token.
    class NotEnabled < Error; end
    NOT_ENABLED = /feature flag is not enabled/i
    # Northflank answered that the resource is not there, the one answer a re-read takes as gone.
    class NotFound < Error
      include Integrations::NotFound
    end
    # Northflank turned the request down as it stands, such as a token whose role may not add notification integrations.
    class Refused < Error; end
    # The token's role may not do this, which a caller can name the permission for.
    class Forbidden < Refused; end
    REFINED = { 400 => Refused, 403 => Forbidden, 404 => NotFound, 409 => Refused, 422 => Refused }.freeze
    VERBS = { "GET" => Net::HTTP::Get, "POST" => Net::HTTP::Post, "PATCH" => Net::HTTP::Patch, "PUT" => Net::HTTP::Put,
              "DELETE" => Net::HTTP::Delete }.freeze

    API_ROOT = "https://api.northflank.com/v1".freeze
    PAGE_SIZE = 100
    MAX_PAGES = 10
    # The notification integration type that posts to an address of one's own.
    RAW_WEBHOOK = "RAW_WEBHOOK".freeze

    def initialize(token)
      @token = token
    end

    # The lists answer a Pages::Read.
    def projects = list("/projects", "projects")

    def project(project_id) = get("/projects/#{segment(project_id)}")

    def services(project_id) = list("/projects/#{segment(project_id)}/services", "services")

    def addons(project_id) = list("/projects/#{segment(project_id)}/addons", "addons")

    def builds(project_id, service_id, limit:)
      get("/projects/#{segment(project_id)}/services/#{segment(service_id)}/build", "per_page" => limit).dig("data", "builds") || []
    end

    def service(project_id, service_id) = get("/projects/#{segment(project_id)}/services/#{segment(service_id)}")["data"] || {}

    # The project's secret groups, each with who it applies to (@northflank/js-client, ListSecretsResult restrictions),
    # and one group with its variables and the addons linked to it (GetSecretdetailsResult secrets.variables and
    # addonSecrets, GET /v1/projects/{projectId}/secrets/{secretId}/details). Both need the token's role to read
    # secret groups, and the values are read only in memory.
    def secret_groups(project_id) = list("/projects/#{segment(project_id)}/secrets", "secrets")

    def secret_group(project_id, secret_id) = get("/projects/#{segment(project_id)}/secrets/#{segment(secret_id)}/details")["data"] || {}

    def addon(project_id, addon_id) = get("/projects/#{segment(project_id)}/addons/#{segment(addon_id)}")["data"] || {}

    def deployments(project_id, service_id, limit:)
      get("/projects/#{segment(project_id)}/services/#{segment(service_id)}/deployments", "per_page" => limit).dig("data", "deployments") || []
    end

    # kind is services or addons, the two that run containers.
    def containers(project_id, kind, resource_id, limit:)
      get("/projects/#{segment(project_id)}/#{kind}/#{segment(resource_id)}/containers", "per_page" => limit).dig("data", "containers") || []
    end

    def backups(project_id, addon_id, limit:)
      get("/projects/#{segment(project_id)}/addons/#{segment(addon_id)}/backups", "per_page" => limit).dig("data", "backups") || []
    end

    def jobs(project_id) = list("/projects/#{segment(project_id)}/jobs", "jobs")

    def job_runs(project_id, job_id, limit:)
      get("/projects/#{segment(project_id)}/jobs/#{segment(job_id)}/runs", "per_page" => limit).dig("data", "runs") || []
    end

    def build_logs(project_id, service_id, query)
      get("/projects/#{segment(project_id)}/services/#{segment(service_id)}/build-logs", { "queryType" => "range" }.merge(query))["data"] || []
    end

    # kind is services or addons, the two things that run and log in a project. query uses Northflank's own parameter
    # names, such as startTime and textIncludes.
    def logs(project_id, kind, resource_id, query)
      get("/projects/#{segment(project_id)}/#{kind}/#{segment(resource_id)}/logs", { "queryType" => "range" }.merge(query))["data"] || []
    end

    def metrics(project_id, kind, resource_id, query)
      get("/projects/#{segment(project_id)}/#{kind}/#{segment(resource_id)}/metrics", { "queryType" => "range" }.merge(query))["data"] || {}
    end

    def job(project_id, job_id) = get("/projects/#{segment(project_id)}/jobs/#{segment(job_id)}")["data"] || {}

    # A workflow's whole definition, its triggers' tokens included (@northflank/js-client, GetWorkflowResult, GET
    # /v1/projects/{projectId}/workflows/{workflowId}).
    def workflow(project_id, workflow_id) = get("/projects/#{segment(project_id)}/workflows/#{segment(workflow_id)}")["data"] || {}

    # Replaces a workflow's definition, which Northflank takes whole (UpdateWorkflowData, POST
    # /v1/projects/{projectId}/workflows/{workflowId}).
    def update_workflow(project_id, workflow_id, body)
      changing(Net::HTTP::Post, "/projects/#{segment(project_id)}/workflows/#{segment(workflow_id)}", body)["data"] || {}
    end

    # The token's team's notification integrations, each with its type and webhook address but never its secret
    # (@northflank/js-client, ListNotificationsResult, GET /v1/integrations/notifications), read only to find one Firefight
    # made at the same address.
    def notifications = list("/integrations/notifications", "notificationIntegrations")

    # A RAW_WEBHOOK notification integration for the events named, restricted to the projects named, sending secret in its
    # X-Northflank-Notification-Integration-Token header (@northflank/js-client, CreateNotificationData, POST
    # /v1/integrations/notifications). Its role needs Account, Observability, Notifications, Create.
    def create_notification(name:, url:, secret:, events:, projects:)
      body = { "name" => name, "type" => RAW_WEBHOOK, "webhook" => url, "secret" => secret, "restricted" => true, "projects" => projects,
               "events" => events.index_with(true) }
      changing(Net::HTTP::Post, "/integrations/notifications", body)["data"] || {}
    end

    def delete_notification(notification_id) = changing(Net::HTTP::Delete, "/integrations/notifications/#{segment(notification_id)}")

    # Any call inside a project, as the api_request tool asks for it. The body goes as JSON and the query options encoded.
    def request(verb, project_id, path, body = nil, query = {})
      uri = URI.parse("#{API_ROOT}/projects/#{segment(project_id)}/#{path}")
      uri.query = encode(query) if query.any?
      request = VERBS.fetch(verb).new(uri)
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      send_request(uri, request)
    end

    private

    # Every page of a list, as a Pages::Read, following the cursor Northflank gives while it says there is a next page
    # (@northflank/js-client, ApiCallResponse pagination). A list past MAX_PAGES is cut short and says so.
    def list(path, key)
      Pages.read(max_pages: MAX_PAGES) do |cursor|
        body = get(path, { "per_page" => PAGE_SIZE, "cursor" => cursor }.compact)
        pagination = body["pagination"] || {}
        [ body.dig("data", key) || [], (pagination["cursor"] if pagination["hasNextPage"]) ]
      end
    end

    def changing(verb, path, body = nil)
      uri = URI.parse("#{API_ROOT}#{path}")
      request = verb.new(uri)
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      send_request(uri, request)
    end

    def get(path, query = {})
      uri = URI.parse("#{API_ROOT}#{path}")
      uri.query = encode(query) if query.any?
      send_request(uri, Net::HTTP::Get.new(uri))
    end

    def send_request(uri, request)
      request["Authorization"] = "Bearer #{@token}"
      Http.json(uri, request, error_class: Error, provider_name: "Northflank", rate_limited: RateLimited,
                              refine: ->(code, reason) { [ 401, 403 ].include?(code) && reason.match?(NOT_ENABLED) ? NotEnabled : REFINED[code] })
    end

    # A repeated parameter such as metricTypes is sent once per value, which is how Northflank reads a list.
    def encode(query)
      pairs = query.compact.flat_map { |name, value| Array(value).map { |each| [ name.to_s, each.to_s ] } }
      URI.encode_www_form(pairs)
    end

    def segment(value) = Http.segment(value)
  end
end
