module Integrations
  # Calls to Render's public REST API with a workspace's own API key, for the Render integration. Paths, parameters
  # and answers are the ones in Render's OpenAPI spec (api-docs.render.com/openapi/render-public-api-1.json), with list
  # parameters encoded as the Go client generated from it does (render-oss/render-mcp-server, pkg/client/client_gen.go).
  class RenderApi
    class Error < Integrations::Error; end
    # Render answered that the resource is not there (spec, 404NotFound), the one answer a re-read takes as gone.
    class NotFound < Error
      include Integrations::NotFound
    end
    # Render turned the request down as it stands, such as a webhook on a plan without them (spec, 400BadRequest and the
    # like), as opposed to a key it does not accept.
    class Refused < Error; end
    REFINED = { 400 => Refused, 402 => Refused, 403 => Refused, 404 => NotFound, 409 => Refused, 422 => Refused }.freeze

    API_ROOT = "https://api.render.com/v1".freeze
    PROVIDER = "Render".freeze
    # Render answers at most this many rows a page, and a list is read for at most this many pages.
    PAGE_SIZE = 100
    MAX_PAGES = 10

    def initialize(api_key)
      @api_key = api_key
    end

    def owner(owner_id) = get("/owners/#{segment(owner_id)}")

    # The workspaces the key can read, as a Pages::Read of owners with their id and name (GET /v1/owners, "List
    # workspaces", api-docs.render.com/reference/list-owners).
    def owners = list("/owners", "owner")

    # Every service, Postgres database and Key Value instance in the workspace, each as a Pages::Read that says whether the
    # list was read to its end. ownerId is comma separated, as the spec's form style without explode asks.
    def services(owner_id) = list("/services", "service", "ownerId" => owner_id)

    def postgres_databases(owner_id) = list("/postgres", "postgres", "ownerId" => owner_id)

    def key_values(owner_id) = list("/key-value", "keyValue", "ownerId" => owner_id)

    def service(service_id) = get("/services/#{segment(service_id)}")

    def postgres(postgres_id) = get("/postgres/#{segment(postgres_id)}")

    def key_value(key_value_id) = get("/key-value/#{segment(key_value_id)}")

    def deploys(service_id, limit:) = page("/services/#{segment(service_id)}/deploys", "deploy", "limit" => limit)

    # One deploy by its id (spec, GET /services/{serviceId}/deploys/{deployId}).
    def deploy(service_id, deploy_id) = get("/services/#{segment(service_id)}/deploys/#{segment(deploy_id)}")

    # A service's own environment variables, each a key and its value (spec, GET /services/{serviceId}/env-vars,
    # envVarWithCursor), read only in memory for where its settings point.
    def env_vars(service_id) = list("/services/#{segment(service_id)}/env-vars", "envVar")

    # The environment groups of a workspace, each naming the services linked to it (spec, GET /env-groups, envGroupMeta
    # serviceLinks), and one group with its variables (GET /env-groups/{envGroupId}, envGroup envVars). The list's rows
    # carry no cursor, so one page of PAGE_SIZE is read and a full page is taken as possibly cut short.
    def env_groups(owner_id) = Array(get("/env-groups", "ownerId" => owner_id, "limit" => PAGE_SIZE))

    def env_group(env_group_id) = get("/env-groups/#{segment(env_group_id)}")

    def custom_domains(service_id) = list("/services/#{segment(service_id)}/custom-domains", "customDomain")

    def events(service_id, query) = page("/services/#{segment(service_id)}/events", "event", query)

    # One page of log lines. ownerId and resource are required, and every list filter is sent once per value.
    def logs(query) = get("/logs", query)

    # One time series per label set, for metrics such as cpu, memory or http-requests.
    def metrics(name, query) = Array(get("/metrics/#{name}", query))

    # The instances a service runs now, each its id and when it started (spec, GET /services/{serviceId}/instances).
    def instances(service_id) = Array(get("/services/#{segment(service_id)}/instances"))

    # A service's one-off jobs, newest first, and one by its id (spec, GET /services/{serviceId}/jobs and
    # /services/{serviceId}/jobs/{jobId}, render.com/docs/one-off-jobs).
    def jobs(service_id, limit:) = page("/services/#{segment(service_id)}/jobs", "job", "limit" => limit)

    def job(service_id, job_id) = get("/services/#{segment(service_id)}/jobs/#{segment(job_id)}")

    # The workflows of a workspace and one by its id, a workflow's tasks, its task runs newest first, the runs one root
    # run started, and one task run with its attempts (spec, GET /workflows, /workflows/{workflowId}, /tasks and
    # /task-runs filtered by workflowId or rootTaskRunId, and /task-runs/{taskRunId}).
    def workflows(owner_id) = list("/workflows", "workflow", "ownerId" => owner_id)

    def workflow(workflow_id) = get("/workflows/#{segment(workflow_id)}")

    def tasks(workflow_id) = list("/tasks", "task", "workflowId" => workflow_id)

    def task_runs(workflow_id, limit:) = page("/task-runs", "taskRun", "workflowId" => workflow_id, "limit" => limit)

    def child_task_runs(root_run_id) = page("/task-runs", "taskRun", "rootTaskRunId" => root_run_id, "limit" => PAGE_SIZE)

    def task_run(task_run_id) = get("/task-runs/#{segment(task_run_id)}")

    def restart_service(service_id) = post("/services/#{segment(service_id)}/restart")

    def restart_postgres(postgres_id) = post("/postgres/#{segment(postgres_id)}/restart")

    def rollback(service_id, deploy_id) = post("/services/#{segment(service_id)}/rollback", "deployId" => deploy_id)

    def scale(service_id, instances) = post("/services/#{segment(service_id)}/scale", "numInstances" => instances)

    # Cancels a deploy still in progress, answering it as Render now has it (spec, POST
    # /services/{serviceId}/deploys/{deployId}/cancel, not for cron jobs).
    def cancel_deploy(service_id, deploy_id) = post("/services/#{segment(service_id)}/deploys/#{segment(deploy_id)}/cancel")

    # Starts a deploy as body says, with commitId, imageUrl, clearCache or deployMode, answering the deploy, or nil when
    # Render answers 202 with none (spec, POST /services/{serviceId}/deploys).
    def trigger_deploy(service_id, body) = post("/services/#{segment(service_id)}/deploys", body)

    # Where a service, a Postgres database and a Key Value instance are suspended and resumed (spec, POST
    # /services/{serviceId}/suspend, /postgres/{postgresId}/suspend, /key-value/{keyValueId}/suspend and each one's
    # resume, answering 202 with no body).
    SUSPENDABLE = { service: "services", postgres: "postgres", key_value: "key-value" }.freeze

    def suspend(kind, id) = post("/#{SUSPENDABLE.fetch(kind)}/#{segment(id)}/suspend")

    def resume(kind, id) = post("/#{SUSPENDABLE.fetch(kind)}/#{segment(id)}/resume")

    # The workspace's webhooks, each with its url and secret (spec, GET /webhooks, webhookWithCursor), read only to find one
    # Firefight registered before at the same address.
    def webhooks(owner_id) = list("/webhooks", "webhook", "ownerId" => owner_id)

    # A webhook for the event types named, answering its id and the secret it signs with (spec, POST /webhooks, 201).
    def create_webhook(owner_id, name:, url:, events:)
      post("/webhooks", "ownerId" => owner_id, "name" => name, "url" => url, "enabled" => true, "eventFilter" => events)
    end

    # Switches back on a webhook Render switched off after its deliveries kept failing (render.com/docs/webhooks, Delivery
    # failures and retries), with the event types named, answering it as Render now has it (spec, PATCH
    # /webhooks/{webhookId}, enabled and eventFilter).
    def update_webhook(webhook_id, events:) = patch("/webhooks/#{segment(webhook_id)}", "enabled" => true, "eventFilter" => events)

    def delete_webhook(webhook_id) = delete("/webhooks/#{segment(webhook_id)}")

    # Any GET of the public API, by its path under API_ROOT, for the general read (Integrations::ApiReads), which checks
    # the path before it gets here.
    def read(path, query) = get(path, query)

    private

    # Every page of a list, which Render answers as an array of { cursor, <key> } pairs, up to MAX_PAGES.
    def list(path, key, query = {})
      Pages.read(max_pages: MAX_PAGES) do |cursor|
        answered = Array(get(path, query.merge("limit" => PAGE_SIZE, "cursor" => cursor)))
        [ answered.filter_map { |pair| pair[key] }, (answered.last&.dig("cursor") if answered.size == PAGE_SIZE) ]
      end
    end

    def page(path, key, query) = Array(get(path, query)).filter_map { |pair| pair[key] }

    def get(path, query = {})
      uri = URI.parse("#{API_ROOT}#{path}")
      encoded = encode(query)
      uri.query = encoded if encoded.present?
      send_request(uri, Net::HTTP::Get.new(uri))
    end

    def post(path, body = nil) = changing(Net::HTTP::Post, path, body)

    def patch(path, body) = changing(Net::HTTP::Patch, path, body)

    def changing(method, path, body)
      uri = URI.parse("#{API_ROOT}#{path}")
      request = method.new(uri)
      if body
        request["Content-Type"] = "application/json"
        request.body = body.to_json
      end
      send_request(uri, request)
    end

    def delete(path)
      uri = URI.parse("#{API_ROOT}#{path}")
      send_request(uri, Net::HTTP::Delete.new(uri))
    end

    def send_request(uri, request)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Accept"] = "application/json"
      Http.json(uri, request, error_class: Error, provider_name: PROVIDER, refine: ->(code, _reason) { REFINED[code] })
    end

    # A list value is sent once per value (resource=a&resource=b), which is how /logs and /metrics read one.
    def encode(query)
      pairs = query.compact.flat_map { |name, value| Array(value).map { |each| [ name.to_s, each.to_s ] } }
      URI.encode_www_form(pairs)
    end

    def segment(value) = Http.segment(value)
  end
end
